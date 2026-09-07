import { createFileRoute, redirect } from "@tanstack/react-router";
import { HelpTip } from "@/components/help-tip";
import { useEffect, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";
import { Loader2, UserPlus, Copy } from "lucide-react";
import { brand } from "@/config/brand";
import { listTeam, inviteMember, setMemberActive, setMemberRole } from "@/lib/team.functions";
import { usePlanFeatures } from "@/hooks/use-plan-features";
import { PlanUsageBadge } from "@/components/plan-usage-badge";

export const Route = createFileRoute("/app/equipe")({
  head: () => ({ meta: [{ title: `${brand.name} — Equipe` }] }),
  beforeLoad: ({ context }: any) => {
    const r = context?.membership?.role;
    if (r !== "owner" && r !== "admin") throw redirect({ to: "/app/dashboard" });
  },
  component: EquipePage,
});

function EquipePage() {
  const ctx = Route.useRouteContext();
  const isOwner = ctx.membership?.role === "owner";
  const list = useServerFn(listTeam);
  const invite = useServerFn(inviteMember);
  const toggleActive = useServerFn(setMemberActive);
  const changeRole = useServerFn(setMemberRole);
  const plan = usePlanFeatures();

  const [members, setMembers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"admin" | "atendente">("atendente");
  const [busy, setBusy] = useState(false);
  const [tempPwd, setTempPwd] = useState<string | null>(null);

  async function reload() {
    setLoading(true);
    try { const r = await list(); setMembers(r.members); }
    catch (e: any) { toast.error(e?.message); }
    finally { setLoading(false); }
  }

  useEffect(() => { void reload(); }, []);

  async function doInvite(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setTempPwd(null);
    try {
      const r = await invite({ data: { email, role } });
      setEmail("");
      toast.success("Membro adicionado");
      if (r.tempPassword) {
        setTempPwd(r.tempPassword);
      }
      await Promise.all([reload(), plan.refresh()]);
    } catch (e: any) { toast.error(e?.message); }
    finally { setBusy(false); }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">Equipe <HelpTip text="Convide atendentes, defina papéis (admin/atendente) e controle quem pode ver e responder cada conversa." /></h1>
          <p className="text-sm text-muted-foreground">Gerencie quem tem acesso a esta empresa.</p>
        </div>
        {!plan.loading && (
          <PlanUsageBadge label="usuários" used={plan.usage.usuarios} limit={plan.limites.usuarios} />
        )}
      </div>

      <Card className="p-5">
        <h2 className="font-semibold mb-3 flex items-center gap-2"><UserPlus className="size-4" /> Convidar membro</h2>
        <form onSubmit={doInvite} className="flex flex-wrap gap-3 items-end">
          <div className="flex-1 min-w-[220px]">
            <Label>Email</Label>
            <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="pessoa@empresa.com" />
          </div>
          <div className="w-44">
            <Label>Papel</Label>
            <Select value={role} onValueChange={(v) => setRole(v as any)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="atendente">Atendente</SelectItem>
                <SelectItem value="admin">Admin</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button type="submit" disabled={busy}>
            {busy ? <Loader2 className="size-4 mr-1.5 animate-spin" /> : <UserPlus className="size-4 mr-1.5" />}
            Adicionar
          </Button>
        </form>
        {tempPwd && (
          <div className="mt-4 rounded-md border bg-amber-500/10 p-3 text-sm">
            <div className="font-medium mb-1">Senha temporária gerada</div>
            <div className="text-xs text-muted-foreground mb-2">Envie ao membro. No primeiro acesso ele será obrigado a trocar.</div>
            <div className="flex items-center gap-2">
              <code className="bg-background px-2 py-1 rounded text-xs flex-1 break-all">{tempPwd}</code>
              <Button size="sm" variant="outline" onClick={() => { navigator.clipboard.writeText(tempPwd); toast.success("Copiado"); }}>
                <Copy className="size-3.5" />
              </Button>
            </div>
          </div>
        )}
      </Card>

      <Card className="overflow-hidden">
        <div className="grid grid-cols-12 text-xs font-medium text-muted-foreground bg-muted/50 px-4 py-2">
          <div className="col-span-5">Membro</div>
          <div className="col-span-3">Papel</div>
          <div className="col-span-2">Status</div>
          <div className="col-span-2 text-right">Ações</div>
        </div>
        {loading ? (
          <div className="p-6 grid place-items-center"><Loader2 className="animate-spin text-muted-foreground" /></div>
        ) : members.length === 0 ? (
          <div className="p-6 text-center text-sm text-muted-foreground">Sem membros.</div>
        ) : (
          <ul className="divide-y">
            {members.map((m) => (
              <li key={m.id} className="grid grid-cols-12 px-4 py-3 items-center text-sm">
                <div className="col-span-5 min-w-0">
                  <div className="font-medium truncate">{m.nome || m.email || m.user_id}</div>
                  <div className="text-xs text-muted-foreground truncate">{m.email}</div>
                </div>
                <div className="col-span-3">
                  {isOwner && m.role !== "owner" ? (
                    <Select value={m.role} onValueChange={(v) =>
                      changeRole({ data: { memberId: m.id, role: v as any } }).then(reload).catch((e) => toast.error(e?.message))
                    }>
                      <SelectTrigger className="h-8 w-32"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="admin">Admin</SelectItem>
                        <SelectItem value="atendente">Atendente</SelectItem>
                      </SelectContent>
                    </Select>
                  ) : (
                    <Badge variant="outline" className="capitalize">{m.role}</Badge>
                  )}
                </div>
                <div className="col-span-2">
                  <Badge variant={m.ativo ? "default" : "secondary"} className={m.ativo ? "bg-primary" : ""}>
                    {m.ativo ? "Ativo" : "Inativo"}
                  </Badge>
                </div>
                <div className="col-span-2 text-right">
                  {m.role !== "owner" && (
                    <Button size="sm" variant="outline" onClick={() =>
                      toggleActive({ data: { memberId: m.id, ativo: !m.ativo } }).then(reload).catch((e) => toast.error(e?.message))
                    }>
                      {m.ativo ? "Desativar" : "Ativar"}
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
