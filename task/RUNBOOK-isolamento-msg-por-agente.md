# Runbook — Isolamento de mensagens por agente (`agent_message_isolation`)

> Branch `nicolas` · gerado 2026-06-17 · patch: `task/agent-message-isolation.patch`

## 1. O que é
Flag **por inbox** `agent_message_isolation`. Quando **ON**, um agente **não-admin** só vê
mensagens com `agent_id NULL` (públicas: cliente/bot/atividade/template) **ou** `agent_id = ele mesmo`.
Admin vê tudo. **OFF por padrão → zero regressão.** Espelho viewer-aware do `team_message_isolation`.

- Carimbo: `messages.agent_id` = `sender_id` em mensagem **outgoing** de `User` (`Message#set_agent_id_from_sender`).
- Filtro central: módulo **`AgentMessageIsolation`** (`app/services/agent_message_isolation.rb`) reusado em
  `MessageFinder`, `Conversations::ListPreloader`, `ConversationFinder#filter_by_query`, `SearchService` e no
  fallback do `_conversation.json.jbuilder`. Front: `useAgentIsolation.js` + `Message.vue`/`RestrictedMessage.vue`
  (thread) e os previews da lista (`ConversationCard` antigo + `CardMessagePreview*`/`KanbanCard`).

## 2. Aplicar o patch
```bash
cd <repo>
git apply --3way task/agent-message-isolation.patch      # validado: aplica limpo em HEAD
```
**Atenção (tree misturado):** estes arquivos são COMPARTILHADOS com outras features em andamento e o diff
pode trazer hunks não exclusivos do isolamento — revise antes de aplicar num tree já divergente:
`app/models/message.rb`, `app/finders/conversation_finder.rb`, `app/services/conversations/list_preloader.rb`,
`app/views/api/v1/conversations/partials/_conversation.json.jbuilder`, `app/views/api/v1/models/_inbox.json.jbuilder`,
`app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue`. Os demais são exclusivos da feature.

## 3. Rollout (ORDEM IMPORTA)
```bash
bundle install && pnpm install            # se houver deps novas (não há nesta feature)
RAILS_ENV=production bundle exec rails db:migrate   # cria messages.agent_id + inboxes.agent_message_isolation
# BACKFILL antes de ligar a flag em qualquer inbox (senão histórico fica público = fail-open):
RAILS_ENV=production bundle exec rake "messages:backfill_agent_id[<account_id>]"
RAILS_ENV=production bundle exec rake assets:precompile    # zero-downtime
sudo /bin/systemctl restart chatwoot.target               # nicolas: NOPASSWD p/ esse comando exato
```
**Ligar a flag** (só depois do backfill): Settings → Inbox → toggle "Isolamento de mensagens por agente",
ou `inbox.update!(agent_message_isolation: true)`.

## 4. Limitação conhecida (por design, = team isolation)
O isolamento de **conteúdo** é garantido no **carregamento** (REST: MessageFinder/ListPreloader/busca filtram).
No **realtime/websocket** o broadcast é único para todos os membros do inbox → a mensagem de outro agente
**chega** ao navegador e é **mascarada** no front (🔒 "Conteúdo restrito", sem horário). Nunca fica legível,
mas se exigir que nem chegue ao cliente, o passo extra é filtrar no `action_cable_listener` (não feito).

## 5. Testes
- **Specs (todas verdes):** `agent_message_isolation_spec`, `conversations/list_preloader_spec`,
  `search_service_spec` (contexto isolamento), `message_finder_spec`, `inboxes_controller_spec`,
  `useAgentIsolation.spec.js`. Rodar: `bundle exec rspec spec/services/agent_message_isolation_spec.rb spec/services/conversations/list_preloader_spec.rb`.
- **Fixtures de validação manual (staging, conta #1):** `RAILS_ENV=production bundle exec rails runner task/agent_iso_demo_seed.rb`
  cria 4 agentes `iso.agente.{a,b,c,d}@simplexteste.local` (senha `Teste@123456`), inbox "Isolamento Agente (teste)" (flag ON)
  e conv #226. Limpar: `task/agent_iso_demo_cleanup.rb`.

## 6. Landmine NÃO relacionada (pré-existente, achada 2026-06-17)
`ConversationFinder#perform_meta_only` chama `set_count_for_all_conversations`, que **não existe** → quebra se
invocado (hoje é dead code, ninguém chama em app/, mas 3 specs ficam vermelhos). **Não tocado** (fora do escopo
do isolamento). Vem provavelmente do trabalho não-commitado da view "Não Lidas". Corrigir/remover em tarefa própria.
