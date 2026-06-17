# Plano — Isolamento de mensagens **por agente** (por inbox)

| | |
|---|---|
| **Data** | 2026-06-16 |
| **Status** | **Pronto para implementação** — semântica decidida (per-message / coluna nova) |
| **Público-alvo deste doc** | Dev que vai implementar |
| **Stack** | Rails 7.1 + Sidekiq (backend) · Vue 3 + Vuex (dashboard) |
| **Base** | espelho do feature **`team_message_isolation`** já existente neste fork |
| **Esforço estimado** | ~1-2 dias (1 PR backend+frontend) |

---

## 1. Contexto e decisão

Hoje o fork já tem **isolamento de mensagens por TIME** (`team_message_isolation`): com o toggle ligado num inbox, um agente só enxerga as mensagens do **seu time**; as dos outros times aparecem borradas com cadeado (🔒). Admin vê tudo.

Pedido: **mesmo conceito, mas por AGENTE** — cada agente só vê as mensagens que **ele** enviou + as do cliente (públicas); as de outros agentes ficam 🔒.

**Decisão de granularidade (fechada):** **por mensagem**, marcando cada mensagem com o agente dono → **nova coluna `messages.agent_id`** (espelho exato de `messages.team_id`). Isso permite que a **mesma conversa** tenha mensagens de agentes diferentes, cada uma com sua visibilidade.

> Premissa: **admin/supervisor continua vendo tudo** (igual ao team isolation). Toggle **OFF por padrão** → zero mudança no comportamento atual.

---

## 2. O que JÁ existe (o espelho a seguir)

Feature `team_message_isolation`, mapeada em 2026-06-16:

| Camada | Arquivo | O que faz |
|---|---|---|
| Migração | `db/migrate/20260325180133_add_team_message_isolation_to_inboxes.rb` | `add_column :inboxes, :team_message_isolation, :boolean, default:false` |
| Coluna msg | `messages.team_id` (`db/schema.rb`) | tag de time na mensagem |
| Carimbo | `app/models/message.rb` — `before_create :set_team_id_from_conversation` (L71/496) | `self.team_id = Conversation…pick(:team_id)` |
| Re-sync | `app/jobs/conversations/update_messages_team_id_job.rb` | em reatribuição, sincroniza `team_id` de todas as msgs |
| Filtro backend | `app/models/conversation.rb` — `has_many :messages` lambda (L125-137) | quando isolation ON: `team_id IS NULL OR team_id = conversation.team_id` |
| Param permitido | `app/controllers/api/v1/accounts/inboxes_controller.rb` (~L195) | `:team_message_isolation` |
| Payload inbox | `app/views/api/v1/models/_inbox.json.jbuilder` (L23) | `json.team_message_isolation …` |
| Payload msg | `app/views/api/v1/models/_message.json.jbuilder` (L13) | `json.team_id …` |
| Toggle UI | `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` (L798-805, L525) | `SettingsToggleSection v-model="teamMessageIsolation"` |
| Restrição bolha | `app/javascript/dashboard/components-next/message/Message.vue` (L180-212, L763) | `isRestrictedByTeam` → renderiza `RestrictedMessage.vue` |
| Composable | `app/javascript/dashboard/composables/useTeamIsolation.js` | `isMessageRestricted(msg, inbox)` |
| Component 🔒 | `app/javascript/dashboard/components-next/message/RestrictedMessage.vue` | bolha borrada + cadeado |
| Previews | `CardMessagePreview.vue`, `CardMessagePreviewWithMeta.vue`, `KanbanCard.vue` | mostram 🔒 na lista/kanban |
| Reports intactos | `app/models/message.rb` (L232, L301) | first_reply/rate-limit usam `all_messages` (sem filtro) |

---

## 3. Comportamento (fluxo de runtime)

```
Agente envia msg (outgoing) ──> carimba messages.agent_id = sender (o agente)
Cliente envia msg (incoming) ─> agent_id = NULL  (pública, todos veem)
Bot / atividade / template ───> agent_id = NULL  (pública)
        │
Agente abre a conversa
        │
MessageFinder filtra:  agent_id IS NULL  OR  agent_id = EU      (admin = sem filtro)
        │
Front renderiza ──> msg de OUTRO agente vira 🔒 RestrictedMessage
                    (minhas / cliente / atividade = normal)
```

Exemplo (1 conversa):

```
Conversa #123
   "orçamento"  (agent_id = Maria) ─> Maria + admin veem  | João vê 🔒
   "contrato"   (agent_id = João)  ─> João  + admin veem  | Maria vê 🔒
   msg do cliente (agent_id = NULL)─> todos veem
```

---

## 4. ⚠️ Diferença crítica vs. team isolation (LER ANTES DE CODAR)

1. **O filtro é dependente de QUEM olha.** Team filtra por uma propriedade da **conversa** (`team_id`) → independe do espectador, por isso vive na *association* em `conversation.rb`. Agente depende do **espectador** → o filtro tem que ir no **`MessageFinder`** (onde se conhece o `Current.user`). **Não** dá pra reaproveitar a lambda da association.

2. **O carimbo é no momento do ENVIO (sender), não na reatribuição.** Team sobrescreve `team_id` de todas as msgs quando a conversa muda de time (job de re-sync). Aqui **não há re-sync**: `agent_id` é fixado uma vez, pelo remetente. Por isso a mesma conversa pode ter agentes diferentes por mensagem (é o requisito). → **não criar** um `UpdateMessagesAgentIdJob`.

3. **Públicas = `agent_id NULL`** (cliente, bot, atividade, template, automação). Só `outgoing` enviada por `User` recebe `agent_id`.

---

## 5. Fluxo de implementação (ordem)

```
DB ─> carimbo ─> filtro backend ─> payloads (incl. realtime) ─> param inbox
   ─> toggle UI ─> restrição UI ─> previews/kanban ─> i18n ─> backfill ─> testes
```

| # | Etapa | Arquivo | Mudança |
|---|-------|---------|---------|
| 1 | Migração inbox | nova `*_add_agent_message_isolation_to_inboxes.rb` | `add_column :inboxes, :agent_message_isolation, :boolean, default:false` |
| 1 | Migração message | nova `*_add_agent_id_to_messages.rb` | `add_column :messages,:agent_id,:bigint` + `add_index :messages,:agent_id` + `add_foreign_key :messages,:users,column::agent_id,on_delete::nullify` |
| 2 | Carimbar na criação | `app/models/message.rb` | `before_create :set_agent_id_from_sender` (ver §6) |
| 3 | **Filtro backend** | `app/finders/message_finder.rb` (`conversation_messages`, L22) | aplicar isolamento por agente (ver §6) |
| 4 | Payload inbox | `app/views/api/v1/models/_inbox.json.jbuilder` | `json.agent_message_isolation resource.agent_message_isolation` |
| 4 | Payload msg | `app/views/api/v1/models/_message.json.jbuilder` | `json.agent_id message.agent_id` |
| 4 | **Payload realtime** | `app/models/message.rb` → `push_event_data` (e `webhook_data` se aplicável) | incluir `agent_id` (⚠️ senão o 🔒 só aparece após **F5**) |
| 5 | Param permitido | `app/controllers/api/v1/accounts/inboxes_controller.rb` (~L195) | adicionar `:agent_message_isolation` ao lado de `:team_message_isolation` |
| 6 | Toggle no settings | `…/settings/inbox/Settings.vue` (L798-805, L525, init/data) | novo `SettingsToggleSection v-model="agentMessageIsolation"` + data + payload de update |
| 7 | Restrição na bolha | `…/components-next/message/Message.vue` | `isRestrictedByAgent` (compara `message.agent_id` com user atual; admin/atividade bypass); render `RestrictedMessage` (ver §6) |
| 7 | Composable | novo `useAgentIsolation.js` (espelho de `useTeamIsolation.js`) | `isMessageRestricted(msg, inbox, currentUserId)` por agente |
| 8 | Component genérico | `RestrictedMessage.vue` | aceitar prop genérica `label`/`reason` (mantém `teamName` funcionando) p/ exibir "Outro agente" |
| 8 | Previews/Kanban | `CardMessagePreview.vue`, `CardMessagePreviewWithMeta.vue`, `KanbanCard.vue` | mascarar 🔒 também p/ agent-restricted |
| 9 | i18n (en + pt_BR) | locale files | `INBOX_MGMT.SETTINGS_POPUP.AGENT_MESSAGE_ISOLATION(+_SUB_TEXT)`, `CONVERSATION.AGENT_ISOLATION.RESTRICTED_TITLE(+_SUBTITLE)` |
| 10 | Backfill | nova `app/jobs/migration/backfill_messages_agent_id_job.rb` | `Message.where(sender_type:'User', message_type::outgoing).in_batches.update_all('agent_id = sender_id')` |
| 11 | Reports intactos | `app/models/message.rb` (L232/301) | **só validar** que first_reply/rate-limit usam `all_messages` (sem filtro). Não mexer. |
| 12 | Testes | specs | ver §9 |

---

## 6. Snippets de referência (espelhos)

### 6.1 Carimbo — `app/models/message.rb`
```ruby
before_create :set_agent_id_from_sender

# espelho de set_team_id_from_conversation, mas pelo REMETENTE
def set_agent_id_from_sender
  self.agent_id = (sender_id if message_type == 'outgoing' && sender_type == 'User')
end
```

### 6.2 Filtro backend — `app/finders/message_finder.rb`
```ruby
def conversation_messages
  scope = @conversation.messages.where(inbox_id: @conversation.inbox_id)
  apply_agent_isolation(scope)
end

def apply_agent_isolation(scope)
  return scope unless @conversation.inbox&.agent_message_isolation

  user = Current.user
  return scope if user.blank? || account_admin?(user)

  scope.where('messages.agent_id IS NULL OR messages.agent_id = ?', user.id)
end

def account_admin?(user)
  user.account_users.find_by(account_id: @conversation.account_id)&.administrator?
end
```
> `Current.user` já está disponível no contexto do controller. Se preferir não depender de `Current`, passe o user no construtor do `MessageFinder` (o controller tem `current_user`).

### 6.3 Restrição no front — `Message.vue` (espelho de `isRestrictedByTeam`, L206-212)
```js
const currentUserId = computed(() => store.getters.getCurrentUser?.id);

const agentIsolationEnabled = computed(
  () => currentInbox.value?.agent_message_isolation === true
);

const isRestrictedByAgent = computed(() => {
  if (!agentIsolationEnabled.value) return false;
  if (!props.agentId) return false;                       // pública
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return false;
  if (isAdmin.value) return false;                        // admin bypass
  return props.agentId !== currentUserId.value;
});

// combinar com o existente:
const isRestricted = computed(() => isRestrictedByTeam.value || isRestrictedByAgent.value);
```
> Passar `agent_id` como prop `agentId` na renderização da mensagem (igual `teamId`).

---

## 7. Critérios de aceite

- [ ] Toggle "Isolar mensagens por agente" aparece no inbox settings, salva e persiste.
- [ ] **OFF por padrão → comportamento atual 100% inalterado** (regressão zero).
- [ ] ON: agente vê só as próprias msgs + as do cliente; demais = 🔒; **admin vê tudo**; mensagens de atividade visíveis.
- [ ] Mensagem nova de outro agente entra como 🔒 **sem F5** (depende do passo 4-realtime).
- [ ] Lista de conversas e Kanban mostram 🔒 no preview quando restrito.
- [ ] Relatórios e contadores (first response, etc.) **não mudam**.
- [ ] Coexiste com `team_message_isolation` (os dois podem estar ligados).

---

## 8. Armadilhas SPX (pôr no card de PR)

- **Produção:** rodar `db:migrate:status` antes de qualquer deploy; **nunca** `restart` com migration pendente (já derrubou a frota com 500 em cadeia).
- **FK `agent_id`:** usar `on_delete: :nullify` — ao deletar um agente, a msg vira "pública". Decidir se é aceitável (provavelmente sim). **Não** repetir o `ON DELETE RESTRICT` que travou a exclusão de contato (migration `20260330120000`).
- **Realtime payload (passo 4) é o item mais esquecível** e o que mais gera "bug reportado": se `agent_id` não for no payload do ActionCable, o 🔒 só aparece após F5.
- **`MessageFinder` x `Current.user`:** garantir que o user está setado no contexto (vale também para o endpoint de busca/`search` se existir caminho alternativo de listagem).
- **Backfill** deve rodar por conta/global após o deploy; até rodar, mensagens antigas ficam públicas (`agent_id NULL`).

---

## 9. Testes

- **Model** (`message_spec`): `agent_id` carimbado em outgoing de `User`; `NULL` para incoming, bot, atividade, template.
- **Finder** (`message_finder_spec`): isolation ON → agente A vê próprias + públicas; **não** vê as de B; admin vê tudo; isolation OFF → vê tudo.
- **Request** (`inboxes_controller_spec`): `PATCH` do inbox aceita/persiste `agent_message_isolation`.
- **Front** (unit): matriz de `isRestrictedByAgent` (própria / outro agente / pública / atividade / admin / toggle off).
