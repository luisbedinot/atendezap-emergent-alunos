# AtendeZap — Guia do Aluno (Emergent)

Cópia funcional do AtendeZap (SaaS multiempresa: WhatsApp + IA + CRM Kanban)
rodando na Emergent com um **banco isolado próprio** (Supabase self-hosted
compatível: Postgres + GoTrue/Auth + PostgREST/RLS). Nenhuma conexão com o
projeto Supabase original é usada.

## Importar o projeto

1. Na Emergent, inicie um novo projeto e clique em **Adicionar do GitHub**.
2. Conecte seu GitHub se a plataforma solicitar.
3. Escolha **Repositório público** e cole
   `https://github.com/luisbedinot/atendezap-emergent-alunos`.
4. Selecione **main** e feche a janela pelo **X**. O nome do repositório fica
   junto ao campo de mensagem. Envie este prompt:

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
- aplica as migrations em um **banco vazio** e sobe backend + frontend;
- preserva os dados, as chaves e as configurações de integrações em novas execuções;
- aguarda a restauração do ambiente e repete o bootstrap se houver uma falha
  transitória durante a reativação do preview.

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

Em **Nova empresa**, cadastre uma empresa e um responsável. Depois entre com
essa conta para concluir o cadastro da empresa e usar o CRM. O master administra
a plataforma; o responsável usa o painel da empresa.

O agente não deve criar um usuário de teste antes do dono da cópia: o primeiro
cadastro é reservado ao aluno.

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

## Se a Emergent perguntar sobre a IA

Responda: **Sim, ative a IA Gemini com a Chave Universal da Emergent e conclua a instalação e o preview.**

As integrações externas continuam usando as credenciais do próprio aluno.
