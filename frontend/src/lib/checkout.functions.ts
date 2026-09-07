import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { slugify } from "@/lib/tenant";

export const createCheckoutCompany = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { nome: string; plano_slug?: string }) => {
    const nome = String(d.nome || "").trim();
    if (nome.length < 2) throw new Error("Informe o nome da sua empresa.");
    const plano_slug = d.plano_slug ? String(d.plano_slug).toLowerCase().trim() : null;
    return { nome, plano_slug };
  })
  .handler(async ({ context, data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: existing, error: existingErr } = await supabaseAdmin
      .from("company_user")
      .select("company_id")
      .eq("user_id", context.userId)
      .eq("ativo", true)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (existingErr) throw existingErr;
    if (existing?.company_id) return { companyId: existing.company_id as string };

    // Trial days: do plano escolhido (ou starter como fallback).
    const requestedPlan = data.plano_slug || "starter";
    const { data: plan, error: planErr } = await supabaseAdmin
      .from("plan")
      .select("id, trial_days, slug")
      .eq("slug", requestedPlan)
      .eq("ativo", true)
      .maybeSingle();
    if (planErr) throw planErr;
    if (!plan) throw new Error("Plano selecionado não está disponível.");
    const trialDays = Math.max(0, Number(plan.trial_days) || 0);
    const planSlug = plan.slug;

    const slug = `${slugify(data.nome)}-${Math.random().toString(36).slice(2, 6)}`;
    const trialAte = new Date(Date.now() + trialDays * 86400000).toISOString();

    const { data: company, error: companyErr } = await supabaseAdmin
      .from("company")
      .insert({
        nome: data.nome,
        slug,
        primary_color: "#25D366",
        created_by: context.userId,
        status_cobranca: "trial",
        onboarding_completed: false,
        onboarding_step: 0,
        trial_ate: trialAte,
        selected_plan_slug: planSlug,
      } as any)
      .select("id")
      .single();
    if (companyErr || !company) throw new Error(companyErr?.message || "Falha ao criar empresa");

    const { error: memberErr } = await supabaseAdmin.from("company_user").insert({
      user_id: context.userId,
      company_id: company.id,
      role: "owner",
      ativo: true,
    });
    if (memberErr) {
      await supabaseAdmin.from("company").delete().eq("id", company.id);
      throw memberErr;
    }

    const { error: subscriptionErr } = await supabaseAdmin.from("subscription").insert({
      company_id: company.id,
      plan_id: plan.id,
      status: "trialing",
      trial_ends_at: trialAte,
      current_period_end: trialAte,
      metadata: { source: "self_service_trial" },
    });
    if (subscriptionErr) {
      await supabaseAdmin.from("company").delete().eq("id", company.id);
      throw subscriptionErr;
    }

    return { companyId: company.id as string };
  });
