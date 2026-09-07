import { createFileRoute } from "@tanstack/react-router";
import { HelpTip } from "@/components/help-tip";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { brand } from "@/config/brand";
import { Bot, KanbanSquare, MessageCircle, Target, Trophy, AlertTriangle, Clock, UserPlus, DollarSign } from "lucide-react";
import { KpiCard } from "@/components/dashboard/kpi-card";
import { MiniAreaChart, type AreaPoint } from "@/components/dashboard/mini-area-chart";
import { MessageTimeline, type TimelineItem } from "@/components/dashboard/message-timeline";
import { Button } from "@/components/ui/button";
import { Link } from "@tanstack/react-router";

export const Route = createFileRoute("/app/dashboard")({
  head: () => ({ meta: [{ title: `${brand.name} — Dashboard` }] }),
  component: Dashboard,
});

type Period = "today" | "7d" | "30d" | "custom";

interface Stats {
  conversas: number; negociando: number; ganho: number; perda: number;
  respondidasIa: number; recebidas: number; receita: number;
}

function periodRange(p: Period, from?: string, to?: string): { start: Date; end: Date; days: number } {
  const end = new Date();
  if (p === "today") {
    const s = new Date(); s.setHours(0, 0, 0, 0);
    return { start: s, end, days: 1 };
  }
  if (p === "7d") return { start: new Date(Date.now() - 7 * 86400000), end, days: 7 };
  if (p === "30d") return { start: new Date(Date.now() - 30 * 86400000), end, days: 30 };
  const s = from ? new Date(from) : new Date(Date.now() - 7 * 86400000);
  const e = to ? new Date(to) : end;
  return { start: s, end: e, days: Math.max(1, Math.ceil((+e - +s) / 86400000)) };
}

function Dashboard() {
  const ctx = Route.useRouteContext();
  const companyId = ctx.company?.id;
  const [status, setStatus] = useState<"connected" | "connecting" | "disconnected">("disconnected");
  const [period, setPeriod] = useState<Period>("7d");
  const [from, setFrom] = useState<string>("");
  const [to, setTo] = useState<string>("");
  const [stats, setStats] = useState<Stats>({ conversas: 0, negociando: 0, ganho: 0, perda: 0, respondidasIa: 0, recebidas: 0, receita: 0 });
  const [series, setSeries] = useState<AreaPoint[]>([]);
  const [timeline, setTimeline] = useState<TimelineItem[]>([]);
  const [paradas, setParadas] = useState<{ numero: string; nome: string | null; min: number }[]>([]);
  const [followups, setFollowups] = useState<{ id: string; nome: string | null; numero: string; when: string }[]>([]);
  const [novos, setNovos] = useState<number>(0);

  const range = useMemo(() => periodRange(period, from, to), [period, from, to]);

  useEffect(() => { if (companyId) void load(companyId, range); }, [companyId, range.start.getTime(), range.end.getTime()]);

  async function load(cid: string, r: { start: Date; end: Date; days: number }) {
    const startISO = r.start.toISOString();
    const endISO = r.end.toISOString();
    const [{ data: inst }, { data: cards }, { data: stages }, { data: msgs }, { data: last }, { data: cardsNew }] = await Promise.all([
      supabase.from("whatsapp_instances").select("status").eq("company_id", cid).maybeSingle(),
      supabase.from("crm_cards").select("status,stage_id,valor,ultima_em,nome,numero").eq("company_id", cid),
      supabase.from("crm_stage").select("id,tipo").eq("company_id", cid),
      supabase.from("mensagens").select("direcao,autor,created_at,numero,contato_nome").eq("company_id", cid).gte("created_at", startISO).lte("created_at", endISO),
      supabase.from("mensagens").select("id,numero,contato_nome,direcao,autor,texto,created_at").eq("company_id", cid).order("created_at", { ascending: false }).limit(8),
      supabase.from("crm_cards").select("id").eq("company_id", cid).gte("ultima_em", startISO),
    ]);

    setStatus(((inst?.status as any) || "disconnected"));

    const stageMap = new Map((stages ?? []).map((s: any) => [s.id, s.tipo as string]));
    const s: Stats = { conversas: 0, negociando: 0, ganho: 0, perda: 0, respondidasIa: 0, recebidas: 0, receita: 0 };
    (cards ?? []).forEach((c: any) => {
      const t = c.stage_id ? stageMap.get(c.stage_id) : null;
      if (t === "ganho") { s.ganho += 1; s.receita += Number(c.valor ?? 0); }
      else if (t === "perda") s.perda += 1;
      else {
        const st = (c.status || "").toLowerCase();
        if (st.includes("negoci")) s.negociando += 1;
        else s.conversas += 1;
      }
    });

    // Series by day in range
    const days = Math.min(r.days, 30);
    const buckets: AreaPoint[] = [];
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(r.end.getTime() - i * 86400000);
      buckets.push({ label: d.toISOString().slice(5, 10), a: 0, b: 0 });
    }
    const idx = new Map(buckets.map((b, i) => [b.label, i]));
    (msgs ?? []).forEach((m: any) => {
      const k = new Date(m.created_at).toISOString().slice(5, 10);
      const i = idx.get(k); if (i !== undefined && m.direcao === "entrada") { buckets[i].a += 1; }
      if (i !== undefined && m.autor === "ia") buckets[i].b = (buckets[i].b ?? 0) + 1;
      if (m.direcao === "entrada") s.recebidas += 1;
      if (m.autor === "ia") s.respondidasIa += 1;
    });
    setSeries(buckets);
    setStats(s);

    setTimeline(
      (last ?? []).map((m: any) => ({
        id: m.id, nome: m.contato_nome || m.numero, autor: m.autor, texto: m.texto,
        quando: new Date(m.created_at),
      })),
    );

    // "Precisa de você"
    // Conversas paradas há +1h (último msg de entrada sem resposta humana/ia)
    const lastByNumero = new Map<string, { last: any; lastOut: any }>();
    (msgs ?? []).forEach((m: any) => {
      const cur = lastByNumero.get(m.numero) ?? { last: null, lastOut: null };
      if (!cur.last || +new Date(m.created_at) > +new Date(cur.last.created_at)) cur.last = m;
      if (m.direcao === "saida" && (!cur.lastOut || +new Date(m.created_at) > +new Date(cur.lastOut.created_at))) cur.lastOut = m;
      lastByNumero.set(m.numero, cur);
    });
    const oneHourAgo = Date.now() - 3600_000;
    const par: { numero: string; nome: string | null; min: number }[] = [];
    lastByNumero.forEach((v, numero) => {
      if (v.last?.direcao === "entrada" && +new Date(v.last.created_at) < oneHourAgo) {
        par.push({
          numero, nome: v.last.contato_nome,
          min: Math.round((Date.now() - +new Date(v.last.created_at)) / 60000),
        });
      }
    });
    setParadas(par.sort((a, b) => b.min - a.min).slice(0, 6));

    // Follow-ups de hoje
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(); todayEnd.setHours(23, 59, 59, 999);
    const { data: fu } = await supabase
      .from("crm_cards").select("id,nome,numero,follow_up")
      .eq("company_id", cid).not("follow_up", "is", null)
      .gte("follow_up", todayStart.toISOString()).lte("follow_up", todayEnd.toISOString());
    setFollowups((fu ?? []).map((c: any) => ({ id: c.id, nome: c.nome, numero: c.numero, when: c.follow_up })));

    setNovos((cardsNew ?? []).length);
  }

  const taxaIa = stats.recebidas ? Math.round((stats.respondidasIa / stats.recebidas) * 100) : 0;
  const totalConv = useMemo(() => series.reduce((a, b) => a + b.a, 0), [series]);

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="font-display text-[26px] font-extrabold tracking-tight flex items-center gap-2">Dashboard <HelpTip text="Visão geral do seu atendimento: KPIs do dia, últimas mensagens recebidas e conversas que precisam de você." /></h1>
          <p className="text-sm text-muted-foreground">Visão geral · {labelPeriod(period, range)}</p>
        </div>
        <PeriodPicker value={period} onChange={setPeriod} from={from} to={to} setFrom={setFrom} setTo={setTo} status={status} />
      </header>

      <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
        <KpiCard accent icon={<MessageCircle className="size-4" />} label="Conversas" value={totalConv} trend={`${stats.recebidas} recebidas`} />
        <KpiCard icon={<Bot className="size-4" />} label="Resolvidas pela IA" value={stats.respondidasIa} trend={`${taxaIa}% no automático`} />
        <KpiCard icon={<Target className="size-4" />} label="Em negociação" value={stats.negociando} trend={`${stats.conversas} em conversa`} />
        <KpiCard icon={<DollarSign className="size-4" />} label="Receita (ganhos)" value={`R$ ${stats.receita.toLocaleString("pt-BR", { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`} trend={`${stats.ganho} ganhos`} />
      </div>

      <div className="grid lg:grid-cols-[1.6fr_1fr] gap-5">
        <div className="rounded-2xl border border-[color:var(--hairline)] bg-[color:var(--panel)] p-6">
          <div className="flex items-center justify-between mb-1">
            <h3 className="font-display text-[17px] font-semibold">Atendimentos</h3>
            <Trophy className="size-4 text-muted-foreground" />
          </div>
          <p className="text-xs text-muted-foreground mb-4">recebidas vs respondidas pela IA</p>
          <MiniAreaChart data={series} />
        </div>
        <PrecisaDeVoceCard paradas={paradas} followups={followups} novos={novos} />
      </div>

      <div className="rounded-2xl border border-[color:var(--hairline)] bg-[color:var(--panel)] p-6">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h3 className="font-display text-[17px] font-semibold">Últimas mensagens</h3>
            <p className="text-xs text-muted-foreground">atividade recente</p>
          </div>
          <KanbanSquare className="size-4 text-muted-foreground" />
        </div>
        <MessageTimeline items={timeline} empty="Conecte o WhatsApp para começar a ver conversas." />
      </div>
    </div>
  );
}

function labelPeriod(p: Period, r: { start: Date; end: Date }) {
  if (p === "today") return "hoje";
  if (p === "7d") return "últimos 7 dias";
  if (p === "30d") return "últimos 30 dias";
  return `${r.start.toLocaleDateString("pt-BR")} → ${r.end.toLocaleDateString("pt-BR")}`;
}

function PeriodPicker({ value, onChange, from, to, setFrom, setTo, status }: {
  value: Period; onChange: (p: Period) => void;
  from: string; to: string; setFrom: (s: string) => void; setTo: (s: string) => void;
  status: "connected" | "connecting" | "disconnected";
}) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <div className="inline-flex rounded-lg border border-[color:var(--hairline)] bg-[color:var(--panel)] p-1">
        {(["today", "7d", "30d", "custom"] as Period[]).map((p) => (
          <button key={p} onClick={() => onChange(p)}
            className={`px-3 py-1.5 text-[13px] font-semibold rounded-md transition-colors ${
              value === p ? "bg-[color:var(--brand-soft)] text-[color:var(--brand-text)]" : "text-muted-foreground hover:text-foreground"
            }`}>
            {p === "today" ? "Hoje" : p === "7d" ? "7 dias" : p === "30d" ? "30 dias" : "Personalizado"}
          </button>
        ))}
      </div>
      {value === "custom" && (
        <div className="flex items-center gap-1.5">
          <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="bg-[color:var(--panel)] border border-[color:var(--hairline)] rounded-md px-2 py-1.5 text-[13px]" />
          <span className="text-muted-foreground text-sm">→</span>
          <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="bg-[color:var(--panel)] border border-[color:var(--hairline)] rounded-md px-2 py-1.5 text-[13px]" />
        </div>
      )}
      <StatusPill status={status} />
    </div>
  );
}

function PrecisaDeVoceCard({ paradas, followups, novos }: {
  paradas: { numero: string; nome: string | null; min: number }[];
  followups: { id: string; nome: string | null; numero: string; when: string }[];
  novos: number;
}) {
  return (
    <div className="rounded-2xl border border-[color:var(--hairline)] bg-[color:var(--panel)] p-6 flex flex-col">
      <div className="flex items-center gap-2 mb-1">
        <AlertTriangle className="size-4 text-amber-500" />
        <h3 className="font-display text-[17px] font-semibold">Precisa de você</h3>
      </div>
      <p className="text-xs text-muted-foreground mb-4">o que esperar prioridade hoje</p>

      <div className="grid grid-cols-3 gap-2 mb-4">
        <Stat icon={<Clock className="size-3.5" />} label="Paradas +1h" value={paradas.length} />
        <Stat icon={<Target className="size-3.5" />} label="Follow-ups" value={followups.length} />
        <Stat icon={<UserPlus className="size-3.5" />} label="Leads novos" value={novos} />
      </div>

      <div className="space-y-2 flex-1 overflow-auto">
        {paradas.length === 0 && followups.length === 0 && (
          <p className="text-[13px] text-muted-foreground text-center py-6">Nada urgente agora. 🎉</p>
        )}
        {paradas.slice(0, 4).map((p) => (
          <Link key={p.numero} to="/app/conversas" className="flex items-center gap-2 px-2.5 py-2 rounded-lg hover:bg-[color:var(--panel-2)] text-[13px]">
            <span className="size-2 rounded-full bg-amber-500 shrink-0" />
            <span className="truncate flex-1">{p.nome || p.numero}</span>
            <span className="text-muted-foreground text-[11.5px]">{p.min}min</span>
          </Link>
        ))}
        {followups.slice(0, 3).map((f) => (
          <Link key={f.id} to="/app/crm" className="flex items-center gap-2 px-2.5 py-2 rounded-lg hover:bg-[color:var(--panel-2)] text-[13px]">
            <span className="size-2 rounded-full bg-[color:var(--brand)] shrink-0" />
            <span className="truncate flex-1">{f.nome || f.numero}</span>
            <span className="text-muted-foreground text-[11.5px]">{new Date(f.when).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}</span>
          </Link>
        ))}
      </div>

      <Button asChild variant="outline" size="sm" className="mt-3">
        <Link to="/app/conversas">Abrir inbox →</Link>
      </Button>
    </div>
  );
}

function Stat({ icon, label, value }: { icon: any; label: string; value: number }) {
  return (
    <div className="rounded-lg bg-[color:var(--panel-2)] border border-[color:var(--hairline)] px-2.5 py-2">
      <div className="flex items-center gap-1 text-[10.5px] uppercase tracking-wider text-muted-foreground">{icon} {label}</div>
      <div className="text-[18px] font-bold mt-0.5">{value}</div>
    </div>
  );
}

function StatusPill({ status }: { status: "connected" | "connecting" | "disconnected" }) {
  const cfg = status === "connected"
    ? { txt: "Agente conectado", cls: "text-[color:var(--brand-text)] border-[color:var(--brand-soft-strong)] bg-[color:var(--brand-soft)]", dot: "var(--brand)" }
    : status === "connecting"
    ? { txt: "Conectando…", cls: "text-amber-600 dark:text-amber-300 border-amber-500/30 bg-amber-500/10", dot: "rgb(245 158 11)" }
    : { txt: "Desconectado", cls: "text-red-600 dark:text-red-300 border-red-500/30 bg-red-500/10", dot: "rgb(239 68 68)" };
  return (
    <div className={`flex items-center gap-2 ${cfg.cls} border text-[12.5px] font-semibold px-3 py-1.5 rounded-full`}>
      <span className="size-2 rounded-full" style={{ background: cfg.dot }} />
      {cfg.txt}
    </div>
  );
}
