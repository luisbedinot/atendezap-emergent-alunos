# Manual de clonagem — AtendeZap

Este guia separa o que já vem no código do que cada clone precisa configurar. O app inclui painel, CRM, IA, campanhas, integrações e conexão por QR Code, mas **não inclui um servidor Evolution API nem credenciais externas**.

## 1. Clonar e ativar o Lovable Cloud

1. Clone o projeto na Lovable.
2. Ative o Lovable Cloud.
3. Confirme que todas as migrations de `supabase/migrations` foram aplicadas.
4. Verifique se as tabelas `company`, `company_user`, `user_roles`, `plan`, `subscription`, `agent_config`, `whatsapp_instances`, `mensagens`, `crm_cards`, `campaign` e `campaign_target` existem.

Em uma cópia nova, as migrations removem os identificadores do projeto original. O primeiro usuário real cadastrado passa a ser o super administrador do clone.

## 2. Criar o primeiro administrador

Faça isso antes de divulgar a URL:

1. Abra `/entrar?modo=signup`.
2. Cadastre o e-mail do administrador e crie uma senha com pelo menos 8 caracteres.
3. Confirme o e-mail.
4. Entre novamente com a mesma senha.
5. Acesse `/master/painel`.

Se já existia um usuário antes da migration corretiva, autentique-se e execute uma única vez:

```sql
select public.claim_super_admin_if_empty();
```

Essa função só promove o usuário quando ainda não existe super administrador ou quando o e-mail está na lista autorizada.

## 3. Configurar o WhatsApp por QR Code

O QR Code depende de uma instalação externa da **Evolution API v2**. Cadastre estes secrets no backend da Lovable:

```text
EVOLUTION_API_URL=https://evolution.seudominio.com
EVOLUTION_API_KEY=sua-chave
```

Requisitos:

- servidor Evolution com HTTPS;
- integração `WHATSAPP-BAILEYS` habilitada;
- rotas v2 de criação, conexão, estado, webhook, presença e envio;
- acesso do servidor Evolution à URL pública do AtendeZap.

Depois:

1. Entre como empresa.
2. Abra **Conexão**.
3. Clique em **Conectar WhatsApp**.
4. No celular, abra WhatsApp → Aparelhos conectados → Conectar aparelho.
5. Leia o QR Code e aguarde o status **Conectado**.

O app configura automaticamente um webhook com token exclusivo por instância. Não remova o parâmetro `t` da URL criada pelo sistema.

## 4. Configurar a IA

O gateway de IA da Lovable é usado como padrão. Se o projeto exigir uma chave explícita, cadastre `LOVABLE_API_KEY` nos secrets. Planos que liberam provedores externos também podem usar as chaves configuradas na tela avançada do agente.

Antes de testar:

1. Preencha nome do agente e da empresa.
2. Informe produtos, serviços, regras e restrições.
3. Configure horário de atendimento.
4. Envie uma mensagem de texto para o número conectado.

Áudios, documentos, imagens e vídeos sem legenda são identificados, mas não são transcritos nem interpretados nesta versão. A IA recebe uma indicação do tipo de mídia e pede a informação por texto.

## 5. Personalizar cada clone

Edite `src/config/brand.ts` para nome, slogan e cor. Configure também as variáveis públicas:

```text
VITE_SUPPORT_WHATSAPP=5511999999999
VITE_SUPPORT_WHATSAPP_DISPLAY=(11) 99999-9999
VITE_OG_IMAGE_URL=https://seu-dominio.com/og-image.png
```

No backend, `SUPPORT_WHATSAPP` é opcional e acrescenta o contato de suporte aos erros da Evolution. Se essas variáveis não forem definidas, o clone não exibe o número do projeto original.

## 6. Planos e teste grátis

Os planos ficam em `/master/planos`. O teste grátis cria uma assinatura `trialing` vinculada ao plano escolhido, portanto os limites de Pro ou Business são respeitados desde o início.

Configure em cada plano:

- preço;
- dias de trial;
- limites de mensagens, contatos, instâncias e usuários;
- créditos mensais e de trial;
- URL de checkout, quando houver cobrança externa.

## 7. Webhooks de cobrança

O projeto normaliza eventos de Kiwify, Cakto e Perfectpay. Use uma URL distinta por provedor:

```text
POST https://SEU-DOMINIO/api/public/billing/webhook?provider=kiwify
POST https://SEU-DOMINIO/api/public/billing/webhook?provider=cakto
POST https://SEU-DOMINIO/api/public/billing/webhook?provider=perfectpay
```

Cadastre o secret correspondente:

```text
KIWIFY_WEBHOOK_TOKEN
CAKTO_WEBHOOK_TOKEN
PERFECTPAY_WEBHOOK_TOKEN
```

Envie o token pelo header `x-webhook-token` ou `Authorization: Bearer ...`. Tokens na query string não são aceitos. O processamento possui chave idempotente para impedir que o mesmo payload recarregue créditos duas vezes.

Associe cada plano ao identificador do produto presente na URL de checkout. Antes de liberar clientes, teste aprovação, renovação, falha, cancelamento e reembolso em sandbox.

## 8. Worker das campanhas

Sem um agendador, a campanha fica criada, mas não dispara automaticamente. Gere um valor longo e aleatório e cadastre:

```text
CAMPAIGN_WORKER_SECRET=valor-aleatorio-com-32-ou-mais-caracteres
```

Configure um cron confiável para chamar a cada minuto:

```http
POST /api/public/hooks/process-campaigns
x-worker-secret: SEU_CAMPAIGN_WORKER_SECRET
```

O endpoint rejeita chamadas sem secret. Os destinatários são reservados atomicamente para evitar duplicidade quando duas execuções se sobrepõem.

## 9. Google Agenda

Cadastre:

```text
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
GOOGLE_OAUTH_STATE_SECRET
```

`GOOGLE_OAUTH_STATE_SECRET` pode ser omitido no Lovable Cloud quando `SUPABASE_SERVICE_ROLE_KEY` já está disponível no servidor. Nunca use um valor público ou previsível.

No Google Cloud Console, adicione exatamente o domínio do clone:

```text
https://SEU-DOMINIO/api/public/google-callback
```

O estado OAuth expira em 10 minutos e é validado por HMAC.

## 10. Checklist antes de entregar

- [ ] primeiro cadastro acessa `/master/painel`;
- [ ] cadastro exige uma senha conhecida pelo usuário;
- [ ] empresa em trial recebe o plano realmente escolhido;
- [ ] QR Code conecta e o banco salva status `connected`;
- [ ] mensagem recebida aparece no inbox;
- [ ] IA responde e consome um crédito apenas quando há envio;
- [ ] opt-out pausa a IA;
- [ ] CRM atualiza o estágio;
- [ ] campanha dispara pelo worker autenticado sem duplicar alvos;
- [ ] webhook de pagamento duplicado não recarrega créditos novamente;
- [ ] usuário `atendente` não altera plano, créditos, integrações ou tokens;
- [ ] Google OAuth usa o domínio do clone;
- [ ] número de suporte e imagem social pertencem ao dono do clone.

## Uso responsável do WhatsApp

- Não use listas frias nem contatos sem consentimento.
- Respeite opt-out e a janela de atendimento aplicável.
- Aqueça números novos gradualmente.
- Monitore qualidade, bloqueios e falhas.
- Para operações de maior risco ou escala, avalie a WhatsApp Business Platform oficial. Nenhuma integração elimina completamente o risco de bloqueio quando há abuso ou violação das políticas do WhatsApp.
