import { createFileRoute } from "@tanstack/react-router";

/**
 * Worker chamado por pg_cron a cada minuto.
 * Processa até N envios por execução, respeitando intervalos anti-ban.
 */
export const Route = createFileRoute("/api/public/hooks/process-campaigns")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        try {
          const expectedSecret = process.env.CAMPAIGN_WORKER_SECRET;
          const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";
          const suppliedSecret = request.headers.get("x-worker-secret") || bearer;
          if (!expectedSecret) {
            return new Response("worker não configurado", { status: 503 });
          }
          if (!suppliedSecret || suppliedSecret !== expectedSecret) {
            return new Response("não autorizado", { status: 401 });
          }

          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { evoSendText } = await import("@/lib/evolution.server");

          // Promove agendadas que chegaram a hora
          await supabaseAdmin
            .from("campaign")
            .update({ status: "enviando" })
            .eq("status", "agendada")
            .lte("proximo_envio_em", new Date().toISOString());

          const { data: due } = await supabaseAdmin
            .from("campaign")
            .select("*")
            .eq("status", "enviando")
            .lte("proximo_envio_em", new Date().toISOString())
            .limit(10);

          const processed: any[] = [];
          for (const c of (due ?? []) as any[]) {
            // Carrega instância WhatsApp da empresa
            const { data: inst } = await supabaseAdmin
              .from("whatsapp_instances")
              .select("instance_name, status")
              .eq("company_id", c.company_id)
              .maybeSingle();
            if (!inst || inst.status !== "connected") {
              processed.push({ id: c.id, skipped: "sem_whatsapp" });
              continue;
            }

            // Reserva alvos atomicamente. A função SQL usa FOR UPDATE SKIP LOCKED,
            // evitando disparos duplicados quando dois workers rodam juntos.
            const batchSize = 5;
            const processingToken = crypto.randomUUID();
            const { data: pending, error: claimError } = await (supabaseAdmin as any).rpc(
              "claim_campaign_targets",
              { _campaign_id: c.id, _limit: batchSize, _token: processingToken },
            );
            if (claimError) throw claimError;

            if (!pending || pending.length === 0) {
              const { count: remaining } = await supabaseAdmin
                .from("campaign_target")
                .select("id", { count: "exact", head: true })
                .eq("campaign_id", c.id)
                .eq("status", "pendente");
              if ((remaining ?? 0) > 0) {
                processed.push({ id: c.id, skipped: "alvos_em_processamento" });
                continue;
              }
              await supabaseAdmin.from("campaign").update({
                status: "concluida",
                concluido_em: new Date().toISOString(),
              }).eq("id", c.id);
              processed.push({ id: c.id, done: true });
              continue;
            }

            let enviados = 0;
            let falhas = 0;
            for (const t of pending as any[]) {
              try {
                const texto = String(c.mensagem || "").replace(/\{\{nome\}\}/gi, t.contato_nome || "");
                await evoSendText(inst.instance_name, t.contato_numero, texto);
                await (supabaseAdmin as any).from("campaign_target").update({
                  status: "enviado",
                  enviado_em: new Date().toISOString(),
                  processing_token: null,
                  processing_started_at: null,
                }).eq("id", t.id).eq("processing_token", processingToken);
                if (c.created_by) {
                  await supabaseAdmin.from("mensagens").insert({
                    company_id: c.company_id,
                    user_id: c.created_by,
                    numero: t.contato_numero,
                    contato_nome: t.contato_nome,
                    direcao: "saida",
                    autor: "sistema",
                    texto,
                  });
                }
                enviados++;
              } catch (e: any) {
                await (supabaseAdmin as any).from("campaign_target").update({
                  status: "falhou",
                  erro: String(e?.message ?? e).slice(0, 500),
                  processing_token: null,
                  processing_started_at: null,
                }).eq("id", t.id).eq("processing_token", processingToken);
                falhas++;
              }
            }

            // Calcula próximo envio com intervalo aleatório
            const minS = Math.max(2, c.intervalo_min_seg ?? 5);
            const maxS = Math.max(minS, c.intervalo_max_seg ?? 20);
            let nextDelaySeg = Math.floor(minS + Math.random() * (maxS - minS + 1));

            // Anti-ban: pausa longa a cada N envios
            const totalEnviados = (c.total_enviados ?? 0) + enviados;
            const pausaApos = c.pausa_apos_envios ?? 50;
            const pausaDurMin = c.pausa_duracao_min ?? 10;
            if (pausaApos > 0 && Math.floor(totalEnviados / pausaApos) > Math.floor((c.total_enviados ?? 0) / pausaApos)) {
              nextDelaySeg = pausaDurMin * 60;
            }

            await supabaseAdmin.from("campaign").update({
              total_enviados: totalEnviados,
              total_falhas: (c.total_falhas ?? 0) + falhas,
              proximo_envio_em: new Date(Date.now() + nextDelaySeg * 1000).toISOString(),
            }).eq("id", c.id);

            processed.push({ id: c.id, enviados, falhas });
          }

          return Response.json({ ok: true, processed });
        } catch (e: any) {
          console.error("[process-campaigns]", e);
          return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }), { status: 500 });
        }
      },
    },
  },
});
