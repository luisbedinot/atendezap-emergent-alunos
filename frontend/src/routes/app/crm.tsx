import { createFileRoute } from "@tanstack/react-router";
import { HelpTip } from "@/components/help-tip";
import { useEffect, useMemo, useState } from "react";
import {
  DndContext, DragOverlay, PointerSensor, useDroppable, useDraggable, useSensor, useSensors,
  type DragEndEvent, type DragStartEvent,
} from "@dnd-kit/core";
import { supabase } from "@/integrations/supabase/client";
import { useRealtimePolling } from "@/hooks/use-realtime-fallback";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { InitialsAvatar } from "@/components/ui/initials-avatar";
import { toast } from "sonner";
import { Plus, MoreVertical, Sparkles, Pencil, Trash2, Palette } from "lucide-react";
import { brand } from "@/config/brand";
import { LeadDrawer, type LeadCard, type Stage, type Member } from "@/components/crm/lead-drawer";

export const Route = createFileRoute("/app/crm")({
  head: () => ({ meta: [{ title: `${brand.name} — CRM Kanban` }] }),
  component: KanbanPage,
});

const STAGE_COLORS = ["#8AA89A", "#FFB020", "#22B85F", "#FF5A5A", "#3FD27C", "#60A5FA", "#A78BFA", "#F472B6"];

function KanbanPage() {
  const ctx = Route.useRouteContext();
  const companyId = ctx.company?.id ?? "";
  const userId = ctx.user.id;
  const [stages, setStages] = useState<Stage[]>([]);
  const [cards, setCards] = useState<LeadCard[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [selected, setSelected] = useState<LeadCard | null>(null);
  const [newStageOpen, setNewStageOpen] = useState(false);
  const [editingStage, setEditingStage] = useState<Stage | null>(null);
  const [adding, setAdding] = useState(false);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  async function loadAll(cid: string) {
    const [{ data: st }, { data: cd }, { data: mem }] = await Promise.all([
      supabase.from("crm_stage").select("*").eq("company_id", cid).order("ordem", { ascending: true }),
      supabase.from("crm_cards").select("*").eq("company_id", cid).order("ultima_em", { ascending: false }),
      supabase.from("company_user").select("user_id, profiles:user_id(email)").eq("company_id", cid).eq("ativo", true),
    ]);
    setStages((st ?? []) as Stage[]);
    setCards((cd ?? []) as LeadCard[]);
    setMembers(((mem ?? []) as any[]).map((m) => ({ user_id: m.user_id, email: m.profiles?.email ?? null })));
  }

  useEffect(() => {
    if (!companyId) return;
    void loadAll(companyId);
    const ch = supabase.channel(`tenant:${companyId}:crm`)
      .on("postgres_changes", { event: "*", schema: "public", table: "crm_cards", filter: `company_id=eq.${companyId}` },
        () => loadAll(companyId))
      .on("postgres_changes", { event: "*", schema: "public", table: "crm_stage", filter: `company_id=eq.${companyId}` },
        () => loadAll(companyId))
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [companyId]);

  // Local/preview fallback (no Realtime service): poll company-scoped data.
  useRealtimePolling(!!companyId, () => { if (companyId) void loadAll(companyId); }, 5000);

  const byStage = useMemo(() => {
    const m: Record<string, LeadCard[]> = {};
    stages.forEach((s) => (m[s.id] = []));
    cards.forEach((c) => {
      const sid = c.stage_id && m[c.stage_id] ? c.stage_id : stages[0]?.id;
      if (sid) (m[sid] ||= []).push(c);
    });
    return m;
  }, [cards, stages]);

  async function moveCard(id: string, stageId: string) {
    const stage = stages.find((s) => s.id === stageId);
    if (!stage) return;
    const prev = cards;
    setCards((cs) => cs.map((c) => (c.id === id ? { ...c, stage_id: stageId, status: stage.nome } : c)));
    const { error } = await supabase.from("crm_cards").update({ stage_id: stageId, status: stage.nome }).eq("id", id);
    if (error) { setCards(prev); return toast.error(error.message); }
    await supabase.from("lead_evento").insert({
      company_id: companyId, card_id: id, tipo: "mudanca_etapa", descricao: `Movido para ${stage.nome}`,
    });
  }

  async function createStage(nome: string, cor: string) {
    const ordem = stages.length;
    const { error } = await supabase.from("crm_stage").insert({ company_id: companyId, nome, cor, ordem, tipo: "normal" });
    if (error) toast.error(error.message); else toast.success("Etapa criada");
  }
  async function updateStage(id: string, patch: Partial<Stage>) {
    const { error } = await supabase.from("crm_stage").update(patch).eq("id", id);
    if (error) toast.error(error.message);
  }
  async function deleteStage(id: string) {
    if (stages.length <= 1) return toast.error("Mantenha ao menos uma etapa");
    const first = stages.find((s) => s.id !== id);
    if (!first) return;
    await supabase.from("crm_cards").update({ stage_id: first.id, status: first.nome }).eq("stage_id", id);
    const { error } = await supabase.from("crm_stage").delete().eq("id", id);
    if (error) toast.error(error.message); else toast.success("Etapa removida");
  }
  async function reorderStages(orderedIds: string[]) {
    await Promise.all(orderedIds.map((sid, i) => supabase.from("crm_stage").update({ ordem: i }).eq("id", sid)));
  }

  function onDragStart(e: DragStartEvent) { setActiveId(String(e.active.id)); }
  function onDragEnd(e: DragEndEvent) {
    setActiveId(null);
    const { active, over } = e;
    if (!over) return;
    const aId = String(active.id);
    const oId = String(over.id);
    // stage reorder
    if (aId.startsWith("stage:") && oId.startsWith("stage:")) {
      const from = aId.replace("stage:", ""); const to = oId.replace("stage:", "");
      if (from === to) return;
      const ids = stages.map((s) => s.id);
      const fi = ids.indexOf(from), ti = ids.indexOf(to);
      ids.splice(fi, 1); ids.splice(ti, 0, from);
      setStages((ss) => ids.map((id, i) => ({ ...(ss.find((s) => s.id === id)!), ordem: i })));
      void reorderStages(ids);
      return;
    }
    // card drop on stage
    const stageId = oId.startsWith("col:") ? oId.replace("col:", "") : null;
    if (!stageId) return;
    const card = cards.find((c) => c.id === aId);
    if (!card || card.stage_id === stageId) return;
    void moveCard(aId, stageId);
  }

  const activeCard = activeId ? cards.find((c) => c.id === activeId) : null;

  return (
    <div className="space-y-6">
      <header className="flex items-center justify-between gap-4 flex-wrap">
        <div>
          <h1 className="flex items-center gap-2">CRM Kanban <HelpTip text="Funil visual de vendas. Arraste cards entre etapas (Novo lead → Qualificado → Proposta → Fechado) para acompanhar a evolução de cada contato." /></h1>
          <p className="text-sm text-muted-foreground">Arraste cards entre etapas. A IA também move automaticamente.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setNewStageOpen(true)}><Plus className="size-4 mr-1.5" />Nova etapa</Button>
          <Button onClick={() => setAdding(true)}><Plus className="size-4 mr-1.5" />Adicionar do WhatsApp</Button>
        </div>
      </header>

      <DndContext sensors={sensors} onDragStart={onDragStart} onDragEnd={onDragEnd}>
        <div className="grid gap-5" style={{ gridTemplateColumns: `repeat(${Math.max(stages.length,1)}, minmax(280px,1fr))`, overflowX: "auto" }}>
          {stages.map((col) => (
            <Column key={col.id} stage={col} count={(byStage[col.id] ?? []).length}
              onEdit={() => setEditingStage(col)} onDelete={() => deleteStage(col.id)}>
              {(byStage[col.id] ?? []).map((c) => (
                <KCard key={c.id} card={c} onClick={() => setSelected(c)} />
              ))}
              {(byStage[col.id] ?? []).length === 0 && (
                <div className="text-xs text-muted-foreground text-center py-8 border border-dashed border-[var(--border)] rounded-xl">
                  vazio
                </div>
              )}
            </Column>
          ))}
        </div>
        <DragOverlay>{activeCard ? <CardBody card={activeCard} dragging /> : null}</DragOverlay>
      </DndContext>

      <StageDialog open={newStageOpen} onClose={() => setNewStageOpen(false)}
        onSave={(n, c) => { createStage(n, c); setNewStageOpen(false); }} />
      <StageDialog open={!!editingStage} onClose={() => setEditingStage(null)}
        initial={editingStage ?? undefined}
        onSave={(n, c) => { if (editingStage) updateStage(editingStage.id, { nome: n, cor: c }); setEditingStage(null); }} />

      <LeadDrawer card={selected} stages={stages} members={members} companyId={companyId}
        onClose={() => setSelected(null)} onChanged={() => loadAll(companyId)} />

      <AddFromWhatsappDialog open={adding} onClose={() => setAdding(false)}
        companyId={companyId} userId={userId} firstStageId={stages[0]?.id ?? null}
        firstStageNome={stages[0]?.nome ?? "Conversas"}
        onAdded={() => loadAll(companyId)}
        existingNumbers={new Set(cards.map((c) => c.numero))} />
    </div>
  );
}

function Column({ stage, count, children, onEdit, onDelete }:
  { stage: Stage; count: number; children: React.ReactNode; onEdit: () => void; onDelete: () => void }) {
  const { setNodeRef: setColRef, isOver } = useDroppable({ id: `col:${stage.id}` });
  const { attributes, listeners, setNodeRef: setHandleRef } = useDraggable({ id: `stage:${stage.id}` });
  return (
    <div ref={setColRef}
      className={`rounded-2xl border bg-[var(--panel)] p-4 min-h-[480px] transition-colors ${
        isOver ? "border-[var(--brand)]/60" : "border-[var(--border)]"
      }`}>
      <div ref={setHandleRef} {...attributes} {...listeners}
        className="flex items-center gap-2 mb-4 pb-3 border-b border-[var(--border)] cursor-grab">
        <span className="size-2.5 rounded-full" style={{ background: stage.cor, boxShadow: `0 0 8px ${stage.cor}` }} />
        <b className="font-display text-[15px]">{stage.nome}</b>
        <span className="ml-1 text-[11px] text-muted-foreground bg-[var(--panel-2)] px-2 py-0.5 rounded-full">{count}</span>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="ml-auto text-muted-foreground hover:text-foreground p-1" onPointerDown={(e) => e.stopPropagation()}>
              <MoreVertical className="size-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent>
            <DropdownMenuItem onClick={onEdit}><Pencil className="size-3.5 mr-2" />Renomear / cor</DropdownMenuItem>
            <DropdownMenuItem onClick={onDelete} className="text-destructive"><Trash2 className="size-3.5 mr-2" />Excluir</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

function KCard({ card, onClick }: { card: LeadCard; onClick: () => void }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: card.id });
  return (
    <div ref={setNodeRef} {...attributes} {...listeners}
      style={{ opacity: isDragging ? 0.3 : 1, cursor: "grab" }}
      onClick={onClick}>
      <CardBody card={card} />
    </div>
  );
}

function CardBody({ card, dragging }: { card: LeadCard; dragging?: boolean }) {
  const time = new Date(card.ultima_em);
  return (
    <div className={`rounded-xl border bg-[var(--panel-2)] p-4 transition-all ${
      dragging ? "shadow-2xl ring-2 ring-[var(--brand)]/40 rotate-1 border-[var(--brand)]/40" : "border-[var(--border)] hover:border-[var(--brand)]/30"
    }`}>
      <div className="flex items-start gap-3">
        <InitialsAvatar name={card.nome || card.numero} size={36} />
        <div className="min-w-0 flex-1">
          <div className="text-[14px] font-semibold truncate">{card.nome || card.numero}</div>
          <div className="text-[11px] text-muted-foreground font-mono truncate">{card.numero}</div>
        </div>
      </div>
      {card.ultima_mensagem && (
        <p className="text-muted-foreground text-[13px] mt-2.5 line-clamp-2 leading-snug">{card.ultima_mensagem}</p>
      )}
      {card.tags?.length > 0 && (
        <div className="flex flex-wrap gap-1 mt-2">
          {card.tags.map((t) => (
            <span key={t} className="text-[10px] px-1.5 py-0.5 rounded-md bg-[var(--brand)]/15 text-[var(--brand-text)]">{t}</span>
          ))}
        </div>
      )}
      <div className="flex items-center gap-2 mt-3 pt-3 border-t border-[var(--border)]">
        {card.valor != null && Number(card.valor) > 0 && (
          <span className="font-display font-bold text-[14px] text-[var(--brand-text)]">
            R$ {Number(card.valor).toLocaleString("pt-BR")}
          </span>
        )}
        <span className="text-[10px] font-bold text-[var(--brand-text)] bg-[var(--brand)]/12 px-1.5 py-0.5 rounded-md flex items-center gap-1">
          <Sparkles className="size-2.5" /> IA
        </span>
        <span className="ml-auto text-[11px] text-muted-foreground">
          {time.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })} {time.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}
        </span>
      </div>
    </div>
  );
}

function StageDialog({ open, onClose, onSave, initial }:
  { open: boolean; onClose: () => void; onSave: (nome: string, cor: string) => void; initial?: Stage }) {
  const [nome, setNome] = useState(initial?.nome ?? "");
  const [cor, setCor] = useState(initial?.cor ?? STAGE_COLORS[0]);
  useEffect(() => { if (open) { setNome(initial?.nome ?? ""); setCor(initial?.cor ?? STAGE_COLORS[0]); } }, [open, initial?.id]);
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{initial ? "Editar etapa" : "Nova etapa"}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label>Nome</Label><Input value={nome} onChange={(e) => setNome(e.target.value)} autoFocus /></div>
          <div>
            <Label className="flex items-center gap-1.5"><Palette className="size-3.5" />Cor</Label>
            <div className="flex flex-wrap gap-2 mt-2">
              {STAGE_COLORS.map((c) => (
                <button key={c} onClick={() => setCor(c)}
                  className={`size-8 rounded-full ring-2 transition ${cor === c ? "ring-[var(--brand)] scale-110" : "ring-transparent"}`}
                  style={{ background: c }} />
              ))}
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={() => nome.trim() && onSave(nome.trim(), cor)}>Salvar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddFromWhatsappDialog({ open, onClose, companyId, userId, firstStageId, firstStageNome, onAdded, existingNumbers }: {
  open: boolean; onClose: () => void; companyId: string; userId: string;
  firstStageId: string | null; firstStageNome: string;
  onAdded: () => void; existingNumbers: Set<string>;
}) {
  const [convs, setConvs] = useState<{ numero: string; contato_nome: string | null; texto: string; created_at: string }[]>([]);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (!open || !companyId) return;
    void (async () => {
      setLoading(true);
      const { data } = await supabase.from("mensagens")
        .select("numero,contato_nome,texto,created_at").eq("company_id", companyId)
        .order("created_at", { ascending: false }).limit(100);
      const seen = new Set<string>(); const list: typeof convs = [];
      (data ?? []).forEach((m: any) => {
        if (seen.has(m.numero) || existingNumbers.has(m.numero)) return;
        seen.add(m.numero); list.push(m);
      });
      setConvs(list); setLoading(false);
    })();
  }, [open, companyId]);

  async function add(c: any) {
    const { error } = await supabase.from("crm_cards").upsert({
      company_id: companyId, user_id: userId, numero: c.numero, nome: c.contato_nome,
      status: firstStageNome, stage_id: firstStageId,
      ultima_mensagem: c.texto.slice(0, 240), ultima_em: new Date().toISOString(),
    }, { onConflict: "company_id,numero" });
    if (error) return toast.error(error.message);
    toast.success("Adicionado");
    onAdded(); onClose();
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>Conversas recentes do WhatsApp</DialogTitle></DialogHeader>
        {loading ? <div className="text-sm text-muted-foreground py-6 text-center">Carregando…</div>
          : convs.length === 0 ? <div className="text-sm text-muted-foreground py-6 text-center">Nenhuma conversa nova.</div>
          : (
            <ul className="max-h-80 overflow-auto divide-y divide-[var(--border)]">
              {convs.map((c) => (
                <li key={c.numero} className="py-2.5 flex items-center gap-3">
                  <InitialsAvatar name={c.contato_nome || c.numero} size={32} />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium truncate">{c.contato_nome || c.numero}</div>
                    <div className="text-xs text-muted-foreground truncate">{c.texto}</div>
                  </div>
                  <Button size="sm" variant="outline" onClick={() => add(c)}>Adicionar</Button>
                </li>
              ))}
            </ul>
          )}
      </DialogContent>
    </Dialog>
  );
}
