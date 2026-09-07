# AtendeZap — Guia do Aluno (Emergent)

Cópia funcional do AtendeZap (SaaS multiempresa: WhatsApp + IA + CRM Kanban)
rodando na Emergent com um **banco isolado próprio** (Supabase self-hosted
compatível: Postgres + GoTrue/Auth + PostgREST/RLS). Nenhuma conexão com o
projeto Supabase original é usada.

## Importar em 1 prompt

Depois de **importar este repositório** na Emergent, cole **UM** prompt:

> Configure e rode este projeto na Emergent: execute `bash setup/install.sh`
> para provisionar o banco isolado (Postgres + GoTrue + PostgREST), instalar o
> Node 22 e as dependências, aplicar as migrations em um banco vazio e subir o
> preview. Em seguida me diga a URL do preview. O primeiro cadastro em
> `/entrar?modo=signup` deve virar super administrador.

O `setup/install.sh` é **idempotente** e:
- baixa o Node 22 LTS oficial (mesma versão para build e start);
- instala o Postgres 15 e baixa GoTrue + PostgREST (versões fixadas);
- **provisiona o banco sob o supervisor** (processos em foreground com
  auto-restart e logs): `supabase-postgres` → `supabase-db-init` (one-shot
  ordenado) → `supabase-gotrue` → `supabase-postgrest`;
- **gera segredos novos por instalação** (JWT secret, chaves anon/service,
  segredo do proxy de IA) — nada é herdado de outra cópia;
- **descobre automaticamente** a URL pública do ambiente;
- aplica as 26 migrations em um **banco vazio** e sobe backend + frontend.

## Comandos úteis

```bash
bash setup/install.sh            # instalação/boot completa (idempotente)
# banco/auth/rest são gerenciados pelo supervisor:
sudo supervisorctl status supabase-postgres supabase-gotrue supabase-postgrest
sudo supervisorctl restart supabase-gotrue supabase-postgrest   # NUNCA "restart all"
curl $URL/api/health             # {gateway:ok, gotrue:200, postgrest:200}
bash setup/scan-client-secrets.sh  # build + verifica que segredos não vazam (PASS/FAIL)
```

## Primeiro acesso (dono = super admin)

1. Abra `/entrar?modo=signup`, cadastre e-mail + senha (>= 8 caracteres).
2. O **primeiro** usuário cadastrado vira super administrador automaticamente.
3. Você é redirecionado a `/master/painel`. Há alternância clara
   **Entrar / Criar conta** na tela de login.

## IA (Gemini) via Chave Universal Emergent

- A IA padrão é **Gemini** através da **Chave Universal da Emergent**
  (`EMERGENT_LLM_KEY`), servida pelo backend em `POST /api/ai/chat`.
- O gateway/créditos da Lovable **não** são usados.
- O endpoint de IA é **protegido por segredo servidor→servidor**
  (`AI_PROXY_SECRET`): chamadas anônimas retornam **403**; só o servidor SSR
  (que valida usuário/empresa e consome créditos) pode chamá-lo.
- Sem `EMERGENT_LLM_KEY` definido, o endpoint responde `ai_not_configured`
  (sem chamar nada externo).

## Integrações que dependem de configuração do aluno

Sem credenciais, as telas mostram estado "não configurado" e **não** fazem
chamadas externas reais:
- **WhatsApp (Evolution API v2):** defina `EVOLUTION_API_URL` / `EVOLUTION_API_KEY`.
- **Google Agenda:** `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_OAUTH_STATE_SECRET`.
- **Pagamentos (Kiwify/Cakto/Perfectpay):** tokens de webhook por provedor.
- **Campanhas:** `CAMPAIGN_WORKER_SECRET` + cron.

## Realtime

O serviço de Realtime do Supabase **não** é provisionado no preview. As telas
de Inbox e CRM usam um **fallback por consulta periódica (polling ~5s)**,
autenticado e por empresa, com pausa quando a aba está oculta. Isto **não é**
Realtime; o código original de Realtime é preservado e reativado definindo
`VITE_REALTIME_ENABLED=true` quando um Supabase completo estiver conectado.

## Preview x Produção (importante)

- Este preview usa **Postgres local no container** — persistência real dentro
  da sessão do preview, validada por recarregar a página.
- **NÃO** é um banco de produção persistente. Pods do preview podem reiniciar e
  artefatos fora de `/app` podem ser recriados. Para deploy permanente, aponte
  para um Postgres/Supabase gerenciado (mesmas migrations/RLS) — a viabilidade
  no deploy permanente deve ser verificada separadamente.

## O que foi validado

Ver `EMERGENT_VALIDATION.md` para o relatório completo (login, painel master,
empresa, CRM persistente, isolamento entre 2 contas, atualização entre abas,
Gemini sintético, build, ausência de segredos no cliente).
