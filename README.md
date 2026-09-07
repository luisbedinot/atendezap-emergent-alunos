# AtendeZap — cópia Emergent (alunos)

SaaS multiempresa de atendimento no WhatsApp com IA, CRM Kanban, campanhas,
equipe, relatórios e planos. Esta cópia roda **na Emergent** com um **banco
próprio e isolado** (Supabase self-hosted compatível: Postgres + GoTrue/Auth +
PostgREST/RLS). **Não** usa o Supabase original, WhatsApp externo nem o gateway
de IA da Lovable.

## Como rodar (1 prompt)

Depois de **importar este repositório** na Emergent, cole **UM** prompt — veja
o guia completo em **[EMERGENT_ALUNOS.md](./EMERGENT_ALUNOS.md)**:

> Configure e rode este projeto na Emergent: execute `bash setup/install.sh`
> para provisionar o banco isolado (Postgres + GoTrue + PostgREST), instalar o
> Node 22 e as dependências, aplicar as migrations em um banco vazio e subir o
> preview. Em seguida me diga a URL do preview. O primeiro cadastro em
> `/entrar?modo=signup` deve virar super administrador.

## Stack

- React 19 + TypeScript + TanStack Start (SSR) + Vite + Tailwind/shadcn/ui
- Backend FastAPI (gateway): proxy `/api/auth/v1` → GoTrue, `/api/rest/v1` →
  PostgREST, e IA `POST /api/ai/chat` (Gemini via **Chave Universal Emergent**)
- Supabase self-hosted **sob supervisor** (Postgres + GoTrue + PostgREST)

## Comandos úteis

```bash
bash setup/install.sh              # instalação/boot idempotente (fail-fast)
sudo supervisorctl status supabase-postgres supabase-gotrue supabase-postgrest
curl $URL/api/health               # {gateway:ok, gotrue:200, postgrest:200}
bash setup/scan-client-secrets.sh  # build + verifica que segredos não vazam (PASS/FAIL)
```

## Documentação

- **[EMERGENT_ALUNOS.md](./EMERGENT_ALUNOS.md)** — guia do aluno (obrigatório).
- **[MANUAL.md](./MANUAL.md)** — detalhes de clonagem, integrações e checklist.

## Segurança aplicada

- Isolamento multiempresa com RLS; primeiro admin sem UUID/e-mail herdado.
- Campos de plano/cobrança/créditos protegidos; integrações restritas a owner/admin.
- IA protegida por segredo servidor→servidor (`AI_PROXY_SECRET`).
- Segredos gerados por instalação; nunca versionados (só `*.env.example`).

## Integrações que dependem de configuração do aluno

Sem credenciais, as telas mostram "não configurado" e **não** fazem chamadas
externas: WhatsApp (Evolution API v2), Google Agenda, pagamentos
(Kiwify/Cakto/Perfectpay) e campanhas. Realtime usa **polling (~5s)** no preview.
