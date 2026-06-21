# Fase C — Design Executável (UI: identidade da IA + atribuição + tab "IA")

> **@architect (AIOX) — 2026-06-11.** Baseado em `plano/ia-consolidado.md` (§1 D-2/D-3/D-5/D-11/D-12/D-13,
> §4 C1-C10, §5.1-C, §5.2 P3-P6) + dossiê `/tmp/fase-c-exploracao.json` (4 clusters, verificado no working
> tree com Fases 0+A uncommitted em 11/06). Citações arquivo:linha re-verificadas no código real.
>
> **Regras inegociáveis:** working tree only (zero commit); components-next para UI nova; tokens
> `n-*`/`rgb(var(--token))` — **NUNCA `var(--n-*)`**; i18n pt_BR + en em paridade; dark mode validado;
> Playwright light+dark obrigatório.

---

## 0. O que a Fase A já entrega (premissas verificadas)

| API | Onde | Efeito para a Fase C |
|---|---|---|
| Espelho AgentBot captain (`bot_type: :captain`, `captain_assistant_id` único) | `app/models/agent_bot.rb:44-47` | C2/C5/C7 atribuem o **id do espelho**, nunca o do assistant |
| `Captain::Assistant#mirror_agent_bot` (resolve/cria espelho on-demand) | `enterprise/app/models/captain/assistant.rb:57-59` | C5/C7 nunca falham por espelho ausente |
| `AgentBot#push_event_data` já tem **`type: 'agent_bot'`** | `app/models/agent_bot.rb:55-62` | discriminador do C3 já existe no websocket — o REST só precisa espelhar |
| `Conversations::EventDataPresenter#push_meta` já serializa o bot como assignee | `app/presenters/conversations/event_data_presenter.rb:33-34` | C3 não toca o presenter; só alinha o jbuilder REST |
| `POST /assignments` aceita `assignee_type='AgentBot'` + guard 403 admin-only + render `_agent_bot_slim` | `assignments_controller.rb:4,15-48,55` | C2 só faz o plumbing frontend |
| `AssignmentService#assign_agent_bot` limpa humano e seta espelho **no MESMO save** | `app/services/conversations/assignment_service.rb:23-30` | trilho único de C5/C7 (saves separados quebram a invariante) |
| `after_commit kick_captain_pipeline_after_mirror_assignment` → `AssignmentKickJob` | `enterprise/app/models/enterprise/concerns/conversation.rb:19,24-29` | **C7 ganha o re-enfileiramento de graça** — a tool só troca a atribuição |
| Guard A2b: team-change só auto-atribui humano se `assignee_agent_bot_id.blank?` | `app/models/concerns/assignment_handler.rb:13-21` | ordem `assign_ai_agent` → `assign_team` é segura no C5 |
| Inbox `has_many :captain_assistants` (elegibilidade A5) | `enterprise/app/models/enterprise/concerns/inbox.rb:7-11` | validação de elegibilidade de C5/C7/C8 |
| HandoffTool solta o espelho antes do round-robin | `enterprise/lib/captain/tools/handoff_tool.rb:48` | C6 estende a partir daqui |

---

## 1. Decisões de design da fase (DC-x) — incorporam o que veio decidido no brief

### DC-1 — `reply_assignment_gate` NASCE na Fase C em `account.settings` (jsonb), default OFF
`accounts.feature_flags` é **bigint (63 posições úteis) e `config/features.yml` já tem 66 entradas** — flag
nova seria a posição 67, inutilizável (o fork já sofre disso: `useAIAssistantFlag.js:36-37`). Precedente
completo do mecanismo settings: `auto_resolve_after` (`account.rb:34-76` schema, `:90-99` store_accessor,
`accounts_controller.rb:142-146` whitelist, `_account.json.jbuilder:1` serializa `settings` inteiro,
frontend lê `currentAccount.settings.X`). Casa com D-13 ("setting visível, não flag interna"). A Fase D
só adiciona a UI do toggle (D7) — zero retrabalho.

### DC-2 — Fonte do dropdown C2: **store `captainAssistants` + `agent_bot_id`/`inbox_ids` no jbuilder do assistant** (não o store agentBots)
Justificativa:
1. **Uma fonte para 4 consumidores**: C1 (seção settings), C2 (dropdown sidebar), C4 (elegibilidade
   "conta tem ≥1 assistant") e C5 (options da automação) — todos leem `captainAssistants/getRecords`.
2. A policy de `captain/assistants#index` é liberada a **qualquer agente** (`assistant_policy.rb:2-4`),
   necessário ao C4 (agente comum também vê a tab IA); o endpoint `/agent_bots` não tem essa garantia e
   o store `agentBots` não é buscado em nenhuma página de conversa hoje.
3. `avatar_url` precisa entrar no jbuilder de qualquer forma (gap do C1); `agent_bot_id` e `inbox_ids`
   custam 2 linhas + `includes` e **eliminam o N+1 de elegibilidade do C1** e o risco do "find_by nil
   silencioso" (POSTar `assistant.id` em vez do espelho desatribuiria a conversa com HTTP 200 —
   `assignment_service.rb:36-38`).
4. O dropdown filtra `inbox_ids.includes(conversation.inbox_id)` → só assistants **elegíveis àquela
   inbox** aparecem (UX correta; o backend C8 cobre a tentativa direta).

### DC-3 — Discriminador do assignee-IA: `type: 'agent_bot'` (espelha o push_event_data)
O websocket **já** entrega `meta.assignee = {id, name, avatar_url, type: 'agent_bot'}` quando o espelho é
dono (presenter acima). O REST jbuilder passa a emitir o mesmo shape (+ `thumbnail`/`available_name` que
os cards usam). Getters do front passam a checar `assignee.type !== 'agent_bot'` — corrige a colisão
id User×Bot em `getMineChats`/`showSelfAssign` nos dois transportes de uma vez.

### DC-4 — Semântica de counts/scopes com a flag
- `ai_count` **sempre** computado e serializado (campo novo, inofensivo com flag OFF).
- `unassigned_count` e o filtro `assignee_type='unassigned'` excluem conversas da IA **somente com flag
  ON** (D-5/C3); flag OFF = comportamento atual intacto (D-13).
- O scope global `:unassigned` (`conversation.rb:82`) **não muda** (mudá-lo vazaria para
  `FilterService#set_count_for_all_conversations` e mudaria o modo Clássico). Entram dois scopes
  **aditivos** com `EXISTS` restrito a `bot_type=captain` (bot webhook atribuído via coluna não conta
  como IA nem deixa de contar como não-atribuída — ver openQuestion OQ-1).
- `assigned_count` mantém a fórmula derivada `all - unassigned` (`conversation_finder.rb:44`): com flag
  ON passa a incluir a IA. Aceito e registrado: `assigned_count` não alimenta nenhuma tab; o filtro
  `'assigned'` continua sendo "humano atribuído".
- `perform_meta_only` (`conversation_finder.rb:84-97`) é código morto quebrado (chama método de
  `FilterService`) — **não usar nem tocar**; o caminho vivo é `perform_counts_only`.

### DC-5 — Seletor "Agente IA" (C2) visível para admin INDEPENDENTE da flag
D-3 (admin-only) não condiciona à flag, e D-13 não lista o seletor entre o que o modo obrigatório liga.
Manter visível (quando a conta tem assistant elegível à inbox) viabiliza piloto/teste **antes** da
virada. Como tangencia o "Clássico = tudo como hoje" de D-13, está em openQuestions (OQ-3) para sanção.

### DC-6 — Tab condicional "Não atribuídas" via classe de alerta no `ChatTypeTabs` (sem reescrever woot-tabs)
`ChatTypeTabs.vue` é presentational puro sobre `woot-tabs` legacy sem variantes. Reescrever a barra em
components-next está fora do escopo C4; a regra "components-next para UI **nova**" é respeitada criando
apenas o estilo de alerta via `:class` por item + tokens `n-ruby-*` (dark mode de graça). Componentes
novos (seção C1) são components-next.

### DC-7 — C7 sem mensagem de despedida no v1 (transferência silenciosa) + kick automático
A fala pós-tool da IA antiga é dropada pelo re-check `captain_can_respond?`
(`response_builder_job.rb:51,218`) — comportamento DESEJADO (ela não fala por cima da nova). Se a tool
postasse despedida (antes OU depois da troca), o `AssignmentKickJob` veria outgoing como última visível e
**não** cutucaria a nova IA (`assignment_kick_job.rb: return unless last&.incoming?`). Transferência
silenciosa = a nova IA responde o incoming pendente **imediatamente**, com a knowledge dela. A descrição
da tool instrui o LLM a não anunciar a transferência. Mitigação barata do gap AD-11/B4 incluída (§C7.4).

### DC-8 — Vigia (C10): re-execução DIRETA das regras de triagem, nunca re-dispatch de evento
Re-dispatchar `CONVERSATION_CREATED` acordaria webhooks/NotificationListener/ReportingEvent (mensagens e
side-effects duplicados). O job roda `AutomationRules::ConditionsFilterService` +
`AutomationRules::ActionService` diretamente (mesma filosofia do `AssignmentKickJob` da Fase A:
re-executar o entry com re-check). **1 re-triagem + 1 notificação por episódio de orfandade** (dedupe em
`additional_attributes`), senão regras com `send_message` repetiriam a cada tick de 5 min.

---

## 2. Lote F0 — Fundação (sequencial, PRIMEIRO; ~½ dia)

Pequeno e crítico: cria a flag, o setting do vigia, o payload estendido do assistant, o composable da
flag e TODAS as chaves novas de `config/locales` (arquivo compartilhado — centralizado aqui para manter
os lotes disjuntos).

### F0.1 `app/models/account.rb`
- **`SETTINGS_PARAMS_SCHEMA`** (após a linha 44, `captain_auto_resolve_mode`):
  ```ruby
  'reply_assignment_gate': { 'type': %w[boolean null] },
  'orphan_retriage_after': { 'type': %w[integer null], 'minimum': 5, 'maximum': 10_080 },
  ```
  (`orphan_retriage_after` em minutos; mínimo 5 = tick do cron; máximo 7 dias. Precedente
  `auto_resolve_after`, linha 38.)
- **store_accessor** (junto ao bloco das linhas 90-99):
  ```ruby
  store_accessor :settings, :reply_assignment_gate, :orphan_retriage_after
  ```
- **Helper + scope** (perto dos scopes existentes, ~linha 150, precedente `:with_auto_resolve`):
  ```ruby
  def reply_assignment_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(reply_assignment_gate) || false
  end

  scope :with_reply_assignment_gate, -> { where("(settings ->> 'reply_assignment_gate')::boolean IS TRUE") }
  ```

### F0.2 `app/controllers/api/v1/accounts_controller.rb:142-146`
Adicionar `:reply_assignment_gate, :orphan_retriage_after` a `permitted_settings_attributes`
(gravável via `PATCH /api/v1/accounts/:id` já no C; a Fase D só desenha o toggle D7).

### F0.3 `enterprise/app/views/api/v1/models/captain/_assistant.json.jbuilder` (hoje 10 linhas, sem avatar)
```ruby
json.avatar_url resource.avatar_url            # Avatarable; Avatar do front faz fallback por :name
json.agent_bot_id resource.agent_bot&.id       # id do ESPELHO — é o que o POST /assignments espera
json.inbox_ids resource.captain_inboxes.map(&:inbox_id)  # elegibilidade (C1 coluna + C2 filtro)
```
`agent_bot&.id` defensivo: GET nunca cria registro; assistants sem espelho (sync falhou) são filtrados no
front. Não chamar `mirror_agent_bot` em view.

### F0.4 `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb:10-12`
`@assistants = account_assistants.includes(:agent_bot, :captain_inboxes).ordered` — mata o N+1 do F0.3.

### F0.5 NOVO `app/javascript/dashboard/composables/useReplyAssignmentGate.js`
```js
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

export function useReplyAssignmentGate() {
  const { currentAccount } = useAccount();
  const isAssignmentGateEnabled = computed(() =>
    Boolean(currentAccount.value?.settings?.reply_assignment_gate)
  );
  return { isAssignmentGateEnabled };
}
```
Única fonte da flag no front (C4 tabs, C9 None, contextMenu, bulk; Fase D reusa). Componentes Options API
chamam no `setup()`.

### F0.6 `config/locales/en.yml` + `config/locales/pt_BR.yml` (todas as chaves backend novas da fase)
Sob `conversations.captain` (irmã da `assignment_forbidden` da Fase A):
```yaml
# en
assignment_not_eligible: "This AI agent is not eligible for this conversation's inbox"
# pt_BR
assignment_not_eligible: "Este agente IA não é elegível para a caixa de entrada desta conversa"
```
Sob `notifications.notification_title` (molde `notification.rb:132-140`):
```yaml
# en
conversation_orphaned: "[Unassigned] Conversation [ID - %{display_id}] has no owner and needs triage"
# pt_BR
conversation_orphaned: "[Sem dono] A conversa [ID - %{display_id}] está sem responsável e precisa de triagem"
```

### F0 specs
- `spec/models/account_spec.rb` (aditivo): schema aceita boolean/null e inteiro 5..10080; rejeita lixo;
  `reply_assignment_gate_enabled?` default false; scope `with_reply_assignment_gate`.
- `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb` (aditivo): payload
  inclui `avatar_url`, `agent_bot_id` (= espelho), `inbox_ids`.
- Vitest novo `app/javascript/dashboard/composables/specs/useReplyAssignmentGate.spec.js`.

---

## 3. C1 — Seção "Agentes IA" na página de usuários/agentes (Lote F2)

**Onde:** `app/javascript/dashboard/routes/dashboard/settings/agents/Index.vue` (script setup,
components-next, rota já admin-only — `agent.routes.js:24`). Lista humana fecha no `</div>` da linha 277;
slot `#body` fecha na 278.

### C1.1 NOVO `app/javascript/dashboard/routes/dashboard/settings/agents/AIAgentsSection.vue`
Script setup + components-next. Forma final (esqueleto):
```vue
<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Avatar from 'next/avatar/Avatar.vue';

const store = useStore();
const assistants = useMapGetter('captainAssistants/getRecords');
const inboxes = useMapGetter('inboxes/getInboxes');
const uiFlags = useMapGetter('captainAssistants/getUIFlags');

onMounted(() => store.dispatch('captainAssistants/get'));

const inboxNamesFor = assistant =>
  (assistant.inbox_ids || [])
    .map(id => inboxes.value.find(i => i.id === id)?.name)
    .filter(Boolean);
</script>

<template>
  <section v-if="assistants.length" class="mt-8">
    <div class="flex flex-col gap-1 pb-4 border-b border-n-weak">
      <h2 class="text-heading-2 text-n-slate-12">{{ $t('AGENT_MGMT.AI_AGENTS.TITLE') }}</h2>
      <p class="text-body-main text-n-slate-11 mb-0">{{ $t('AGENT_MGMT.AI_AGENTS.DESCRIPTION') }}</p>
    </div>
    <div class="divide-y divide-n-weak">
      <div v-for="assistant in assistants" :key="assistant.id"
           class="flex justify-between flex-row items-start gap-4 py-4">
        <div class="flex items-center gap-4">
          <Avatar :src="assistant.avatar_url" :name="assistant.name" :size="40" hide-offline-status />
          <div class="flex flex-col gap-1.5 items-start">
            <div class="flex items-center gap-2">
              <span class="text-heading-3 text-n-slate-12">{{ assistant.name }}</span>
              <span class="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium
                           bg-n-brand/10 text-n-brand">
                <span class="i-lucide-bot size-3" />
                {{ $t('AGENT_MGMT.AI_AGENTS.BADGE') }}
              </span>
            </div>
            <span v-if="assistant.description" class="text-body-main text-n-slate-11">
              {{ assistant.description }}
            </span>
            <div class="flex items-center gap-1.5 flex-wrap">
              <span class="text-xs text-n-slate-11">{{ $t('AGENT_MGMT.AI_AGENTS.INBOXES_LABEL') }}:</span>
              <template v-if="inboxNamesFor(assistant).length">
                <span v-for="name in inboxNamesFor(assistant)" :key="name"
                      class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-12">{{ name }}</span>
              </template>
              <span v-else class="text-xs text-n-slate-10">{{ $t('AGENT_MGMT.AI_AGENTS.NO_INBOXES') }}</span>
            </div>
          </div>
        </div>
        <!-- read-only: SEM botões de editar/deletar (D-2); gestão na área Agentes IA -->
      </div>
    </div>
  </section>
</template>
```
Notas: read-only por design (D-2); auto-oculta sem assistants; **sem coluna "status"** — assistant não
tem availability (registrado; o plano citava "status" mas não existe campo no modelo). Tokens `n-*` puros
→ dark mode automático. Se `bg-n-brand/10 text-n-brand` não fechar contraste nos 2 temas, fallback
`bg-n-blue-2 text-n-blue-11` (validar no P3/P12).

### C1.2 `Index.vue` — montar a seção
- Import `AIAgentsSection from './AIAgentsSection.vue'`.
- Inserir `<AIAgentsSection />` após o `</div>` da linha 277 (irmão do bloco da lista humana, ainda
  dentro do `<template #body>`).

### C1.3 i18n — `app/javascript/dashboard/i18n/locale/{pt_BR,en}/agentMgmt.json`
```jsonc
"AGENT_MGMT": { "AI_AGENTS": {
  "TITLE":         pt: "Agentes IA"                                   en: "AI Agents",
  "DESCRIPTION":   pt: "Assistentes de IA que atendem conversas nesta conta. A gestão (prompts, knowledge, comportamento) continua na área Agentes IA."
                   en: "AI assistants that handle conversations in this account. Management (prompts, knowledge, behavior) stays in the AI Agents area.",
  "BADGE":         pt: "Agente IA"                                    en: "AI Agent",
  "INBOXES_LABEL": pt: "Caixas de entrada elegíveis"                  en: "Eligible inboxes",
  "NO_INBOXES":    pt: "Nenhuma caixa de entrada elegível"            en: "No eligible inboxes"
}}
```

### C1.4 Specs
Vitest `AIAgentsSection.spec.js`: renderiza N assistants; oculta com lista vazia; badge presente; chips
de inbox mapeiam ids→nomes; sem botões de ação.

---

## 4. C2 — Seletor "Agente IA" no sidebar, admin-only (Lote F1)

### C2.1 `app/javascript/dashboard/api/inbox/conversation.js` (após `assignAgent`, linhas 94-98)
```js
assignAIAgent({ conversationId, agentBotId }) {
  return axios.post(`${this.url}/${conversationId}/assignments`, {
    assignee_id: agentBotId,          // id do ESPELHO (assistant.agent_bot_id) — DC-2
    assignee_type: 'AgentBot',
  });
}
```

### C2.2 `app/javascript/dashboard/store/modules/conversations/actions.js` (após `assignAgent`, linhas 321-339)
```js
assignAIAgent: async ({ dispatch }, { conversationId, agentBotId, rethrow = false }) => {
  try {
    const response = await ConversationApi.assignAIAgent({ conversationId, agentBotId });
    // response.data = _agent_bot_slim (id, name, thumbnail, bot_type, type) → meta.assignee
    dispatch('setCurrentChatAssignee', { conversationId, assignee: response.data });
  } catch (error) {
    if (rethrow) throw error;
  }
},
```
(`setCurrentChatAssignee` → mutation `ASSIGN_AGENT` existente, `conversations/index.js:186-190` — nada
novo no módulo de mutations.)

### C2.3 `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue`
- **setup() (linha 28-33)**: somar `useMapGetter('captainAssistants/getRecords')` (expor como
  `captainAssistants`) e `useReplyAssignmentGate()` (para o C9 abaixo). `mounted()`: `if
  (this.isAdminUser) this.$store.dispatch('captainAssistants/get');`
- **computed novos** (perto de `assignedAgent`, linha 89):
  ```js
  isAdminUser() { return this.currentRole === 'administrator'; },   // padrão já usado na linha 210 pré-fase-0
  aiAgentsList() {
    const inboxId = this.currentChat?.inbox_id;
    return (this.captainAssistants || [])
      .filter(a => a.agent_bot_id && (a.inbox_ids || []).includes(inboxId))   // elegíveis à inbox — DC-2
      .map(a => ({ id: a.agent_bot_id, name: a.name, thumbnail: a.avatar_url, assistantId: a.id }));
  },
  assignedAIAgent() {
    const assignee = this.currentChat?.meta?.assignee;
    return assignee?.type === 'agent_bot' ? assignee : null;
  },
  ```
- **Ajustar `assignedAgent` (linhas 89-91)** para não exibir o bot no dropdown humano:
  ```js
  assignedAgent() {
    const assignee = this.currentChat?.meta?.assignee;
    return assignee && assignee.type !== 'agent_bot' ? assignee : null;
  },
  ```
  (efeito colateral correto: `showSelfAssign` volta a aparecer em conversa da IA — assumir da IA.)
- **method**:
  ```js
  async onClickAssignAIAgent(item) {
    if (!item?.id || this.assignedAIAgent?.id === item.id) return;  // sem "None" aqui (D-11)
    try {
      await this.$store.dispatch('assignAIAgent', {
        conversationId: this.currentChat.id, agentBotId: item.id, rethrow: true,
      });
      useAlert(this.$t('CONVERSATION.CHANGE_AI_AGENT'));
    } catch (error) {
      useAlert(this.$t('CONVERSATION.CHANGE_AI_AGENT_FAILED'));
    }
  },
  ```
  **Nunca** reusar `onConfirmTransferTeam` (dois saves separados — quebraria a invariante, achado Fase A).
- **Template**: bloco novo entre o wrap do dropdown de agente (fecha ~linha 387) e o row de time (~388):
  ```html
  <template v-if="isAdminUser && aiAgentsList.length">
    <div class="wa-assign-row">
      <span class="wa-assign-label">{{ $t('CONVERSATION_SIDEBAR.AI_AGENT.LABEL') }}</span>
    </div>
    <div class="wa-assign-value-wrap">
      <MultiselectDropdown
        :options="aiAgentsList"
        :selected-item="assignedAIAgent"
        :multiselector-title="$t('CONVERSATION_SIDEBAR.AI_AGENT.TITLE')"
        :multiselector-placeholder="$t('CONVERSATION_SIDEBAR.AI_AGENT.PLACEHOLDER')"
        :no-search-result="$t('CONVERSATION_SIDEBAR.AI_AGENT.NO_RESULTS')"
        :input-placeholder="$t('CONVERSATION_SIDEBAR.AI_AGENT.SEARCH_PLACEHOLDER')"
        @select="onClickAssignAIAgent"
      />
    </div>
  </template>
  ```
  Agente comum **não renderiza** o bloco (P4); tentativa via API direta → 403 da Fase A.

### C2.4 i18n — `i18n/locale/{pt_BR,en}/conversation.json`
```jsonc
"CONVERSATION_SIDEBAR": { "AI_AGENT": {
  "LABEL":              pt: "Agente IA"                       en: "AI Agent",
  "TITLE":              pt: "Atribuir agente IA"              en: "Assign AI agent",
  "PLACEHOLDER":        pt: "Selecionar agente IA"            en: "Select AI agent",
  "NO_RESULTS":         pt: "Nenhum agente IA encontrado"     en: "No AI agents found",
  "SEARCH_PLACEHOLDER": pt: "Buscar agentes IA"               en: "Search AI agents"
}},
"CONVERSATION": {
  "CHANGE_AI_AGENT":        pt: "Agente IA atribuído à conversa"                       en: "AI agent assigned to the conversation",
  "CHANGE_AI_AGENT_FAILED": pt: "Não foi possível atribuir o agente IA, tente novamente" en: "Couldn't assign the AI agent, please try again"
}
```

### C2.5 Specs
Vitest: API (`assignAIAgent` POSTa `{assignee_id, assignee_type:'AgentBot'}`), action (dispatch de
`setCurrentChatAssignee` com o payload do bot), computed `aiAgentsList` filtra por elegibilidade e
espelho presente, `assignedAgent` ignora `type==='agent_bot'`.

---

## 5. C3 — Assignee-IA no serializer + scopes + badge (backend: Lote B1 / front: Lote F3)

### C3.1 `app/models/conversation.rb` — scopes aditivos (após linha 84)
```ruby
# Conversas atendidas por IA (espelho captain). EXISTS compõe com qualquer join/distinct do finder
# e ignora bot webhook atribuído via coluna (não é "atendente").
scope :assigned_to_captain, lambda {
  where('EXISTS (SELECT 1 FROM agent_bots WHERE agent_bots.id = conversations.assignee_agent_bot_id ' \
        'AND agent_bots.bot_type = 1)')
}
scope :without_captain_assignee, lambda {
  where('NOT EXISTS (SELECT 1 FROM agent_bots WHERE agent_bots.id = conversations.assignee_agent_bot_id ' \
        'AND agent_bots.bot_type = 1)')
}
```
(`bot_type = 1` = enum `captain`, `agent_bot.rb:44`. O scope `:unassigned` da linha 82 fica intacto — DC-4.)

### C3.2 `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` — branch novo no bloco do assignee (linhas 37-64)
Entre o `if conversation.assignee.present?` (37-53) e o `elsif conversation.assignee_id.present?`
("Agente Removido", 54-63):
```ruby
elsif conversation.assignee_agent_bot&.captain?
  bot = conversation.assignee_agent_bot
  json.assignee do
    json.id bot.id
    json.account_id Current.account&.id
    json.name bot.name
    json.available_name bot.name
    json.avatar_url bot.avatar_url
    json.thumbnail bot.avatar_url
    json.type 'agent_bot'              # discriminador — DC-3 (mesmo shape do push_event_data)
    json.bot_type bot.bot_type
    json.captain_assistant_id bot.captain_assistant_id
  end
```
Sempre serializado (flag ON e OFF) — payload determinístico; o gating fica nos getters (C3.4). Bot
webhook atribuído NÃO entra (mantém o comportamento atual). Exclusividade (Fase A) garante que os
branches são mutuamente exclusivos.
**N+1**: conferir `find_all_conversations`/`ListPreloader` e somar `:assignee_agent_bot` aos `includes`
da lista (em `conversation_finder.rb`, método `find_all_conversations`).

### C3.3 `app/views/api/v1/models/_agent_bot_slim.json.jbuilder` (1-6)
Adicionar:
```ruby
json.type 'agent_bot'
json.available_name resource.name
```
(é o payload que o C2 grava em `meta.assignee` via mutation `ASSIGN_AGENT` — precisa do discriminador.)

### C3.4 `app/javascript/dashboard/store/modules/conversations/getters.js` (Lote F3)
- `getMineChats` (linhas 97-109): `const isAssignedToMe = assignee && assignee.type !== 'agent_bot' &&
  assignee.id === currentUserID;` (bug de colisão corrigido nos DOIS modos).
- `getUnAssignedChats` (linhas 121-131) — assinatura ganha `(_state, _getters, _rootState, rootGetters)`:
  ```js
  const accountId = rootGetters.getCurrentAccountId;
  const gateEnabled = Boolean(
    rootGetters['accounts/getAccount'](accountId)?.settings?.reply_assignment_gate
  );
  // dentro do filter:
  const { assignee } = conversation.meta;
  const isUnAssigned = !assignee || (assignee.type === 'agent_bot' && !gateEnabled);
  ```
  (flag OFF: IA continua contando como não-atribuída = lista local bate com o `unassigned_count` não
  gateado; flag ON: IA sai — D-5/C3.)
- **getter NOVO `getAIChats`**: filter `conversation.meta.assignee?.type === 'agent_bot'` +
  `applyPageFilters` + `sortComparator` (molde `getUnAssignedChats`).

### C3.5 Badge "IA" no card — `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- computed novo (junto a `assignee()`, linhas 133-136): `isAIAssignee() { return
  this.assignee?.type === 'agent_bot'; }`
- Bloco do assignee (466-475): ícone dinâmico + badge **sempre que IA** (independente de `showAssignee`):
  ```html
  <span v-if="isAIAssignee"
        class="inline-flex items-center gap-0.5 rounded px-1 py-0.5 text-[10px] font-semibold uppercase
               bg-n-brand/10 text-n-brand">
    <span class="i-lucide-bot size-3" />
    {{ $t('CHAT_LIST.AI_BADGE') }}
  </span>
  <span v-if="showAssignee && assignee.name" class="conversation--assignee ...">
    <span :class="isAIAssignee ? 'i-lucide-bot' : 'i-lucide-user'" class="size-3" />
    {{ assignee.name }}
  </span>
  ```
  (mesma família de token do badge C1; validar contraste nos 2 temas no P6/P12.)

### C3.6 Specs
- `spec/models/conversation_spec.rb` (aditivo): os 2 scopes — espelho captain conta, bot webhook não,
  humano não, sem dono não.
- Spec de request/jbuilder (em `spec/controllers/api/v1/accounts/conversations_controller_spec.rb`,
  aditivo): conversa com espelho captain → `meta.assignee.type == 'agent_bot'` + name/thumbnail; humano →
  sem `type`; webhook bot → `assignee` ausente.
- Vitest getters: colisão id bot×user não entra em `getMineChats`; `getUnAssignedChats` com flag ON/OFF;
  `getAIChats`.

---

## 6. C4 — Tabs Minhas/IA/Todas + "Não atribuídas" condicional (Lote F3 + counts no Lote B1)

### C4.1 Backend counts — `app/finders/conversation_finder.rb`
- `filter_by_assignee_type` (168-178):
  ```ruby
  when 'unassigned'
    @conversations = ai_tabs_enabled? ? @conversations.unassigned.without_captain_assignee : @conversations.unassigned
  when 'ai'
    @conversations = @conversations.assigned_to_captain
  ```
  - helper privado: `def ai_tabs_enabled? = current_account.reply_assignment_gate_enabled?`
- `compute_all_counts` (245-274):
  - reselect ganha `'conversations.assignee_agent_bot_id'`;
  - SQL externo ganha o join do espelho + 2 mudanças:
    ```sql
    SELECT
      COUNT(*)::int AS all_count,
      COUNT(*) FILTER (WHERE sub.assignee_id = #{uid})::int AS mine_count,
      COUNT(*) FILTER (WHERE sub.assignee_id IS NULL#{' AND ab.id IS NULL' if ai_tabs_enabled?})::int AS unassigned_count,
      COUNT(*) FILTER (WHERE ab.id IS NOT NULL)::int AS ai_count,
      ... (unattended_* inalterados)
    FROM (#{subquery.to_sql}) sub
    LEFT JOIN agent_bots ab ON ab.id = sub.assignee_agent_bot_id AND ab.bot_type = 1
    ```
  - hash de retorno ganha `ai_count: result['ai_count'].to_i`.
- `perform` (49-61) e `perform_counts_only` (64-81): `ai_count: counts[:ai_count]` no hash `count`.
- `find_all_conversations`: somar `:assignee_agent_bot` ao `includes` (C3.2).

### C4.2 `app/views/api/v1/accounts/conversations/meta.json.jbuilder` (1-9) e `index.json.jbuilder` (1-11)
`json.ai_count @conversations_count[:ai_count]` nos DOIS (as duas fontes de meta do store — risco de
payload parcial coberto pelo guard `'ai_count' in payload` do C4.5).

### C4.3 Constantes (Lote F3)
- `app/javascript/dashboard/constants/globals.js:3-7`: `ASSIGNEE_TYPE: { ME: 'me', UNASSIGNED:
  'unassigned', AI: 'ai', ALL: 'all' }`.
- `app/javascript/dashboard/constants/permissions.js:32-53` — entrada nova ENTRE `unassigned` e `all`
  (ordem das chaves dita a ordem das tabs → flag ON: Minhas / [Não atribuídas alerta] / IA / Todas):
  ```js
  ai: {
    count: 'aiCount',
    permissions: [...ROLES, MANAGE_ALL_CONVERSATION_PERMISSIONS, CONVERSATION_PARTICIPATING_PERMISSIONS],
  },
  ```

### C4.4 `app/javascript/dashboard/components/ChatList.vue`
- **setup**: `const { isAssignmentGateEnabled } = useReplyAssignmentGate();` +
  `const captainAssistants = useMapGetter('captainAssistants/getRecords');` +
  `const hasCaptainAgents = computed(() => captainAssistants.value.length > 0);`
- **fetch de elegibilidade** (onMounted): `if (isAssignmentGateEnabled.value)
  store.dispatch('captainAssistants/get');` — falha tolerada (records vazio ⇒ tab IA não renderiza; conta
  sem Captain não quebra).
- **`assigneeTabItems` (224-255)** — filtro + variant + ícone:
  ```js
  const items = filterItemsByPermission(...)
    .filter(({ key }) => {
      if (key === wootConstants.ASSIGNEE_TYPE.AI)
        return isAssignmentGateEnabled.value && hasCaptainAgents.value && !useUnattendedCounts;
      if (key === wootConstants.ASSIGNEE_TYPE.UNASSIGNED &&
          isAssignmentGateEnabled.value && !useUnattendedCounts)
        return (stats.unAssignedCount ?? 0) > 0;          // tab condicional de alerta (D-5)
      return true;
    })
    .map(({ key }) => ({
      key,
      name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
      count: stats[countKeyForTab(key)] ?? 0,
      icon: iconForKey(key),
      variant: key === wootConstants.ASSIGNEE_TYPE.UNASSIGNED && isAssignmentGateEnabled.value
        ? 'alert' : undefined,
    }));
  ```
  - `iconForKey`: `if (key === wootConstants.ASSIGNEE_TYPE.AI) return 'i-lucide-bot';`
  - countKey resolve via permissions map (`aiCount`).
  - **View unattended** (`useUnattendedCounts`): mantém as 3 tabs clássicas com counts unattended —
    não existem counts unattended-por-IA no SQL (ver OQ-2).
- **Lista local (455-462)**: branch novo
  `else if (activeAssigneeTab.value === 'ai') { localConversationList = aiChatsList.value; }` com
  `const aiChatsList = useMapGetter('getAIChats');`
- **`showAssigneeInConversationCard` (257-262)**: somar `|| activeAssigneeTab.value ===
  wootConstants.ASSIGNEE_TYPE.AI`.
- **Fallback de tab órfã** (risco: tab condicional some enquanto ativa → `activeTabIndex = -1`):
  ```js
  watch([() => conversationStats.value.unAssignedCount, isAssignmentGateEnabled], ([count]) => {
    if (isAssignmentGateEnabled.value &&
        activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNASSIGNED &&
        conversationStats.value.updatedOn && count === 0) {
      updateAssigneeTab(wootConstants.ASSIGNEE_TYPE.ME);
    }
  });
  ```
- Tabs continuam num único caminho (`ChatTypeTabs` ← `ChatList` ← `ConversationView`) → home, team,
  label, folder, status etc. cobertos de uma vez (`conversation.routes.js:17-238`).

### C4.5 `app/javascript/dashboard/store/modules/conversationStats.js`
- state (7-15): `aiCount: 0,`
- mutation `SET_CONV_TAB_META` (90-113): destructure `ai_count: aiCount` + guard padrão unattended:
  ```js
  if ('ai_count' in payload) $state.aiCount = aiCount ?? 0;
  ```
  (meta chega por 2 fontes — endpoint `/meta` e `buildConversationList` via `actionHelpers.js:81` — o
  guard evita zerar com payload parcial; C4.2 garante o campo nas duas.)

### C4.6 `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue` (48-65) — DC-6
```html
<woot-tabs-item
  v-for="(item, index) in items"
  :key="item.key"
  class="text-sm [&_a]:font-medium"
  :class="{ 'tab-alert': item.variant === 'alert' }"
  ...
/>
```
CSS scoped com tokens (NUNCA `var(--n-*)`); ajustar os seletores internos ao markup real do
`woot-tabs-item` (li > a > span/badge) na implementação:
```css
.tab-alert :deep(a) { @apply !text-n-ruby-11; }
.tab-alert :deep(a:hover) { @apply !text-n-ruby-12; }
.tab-alert :deep(.badge) { @apply bg-n-ruby-9/20 text-n-ruby-11; }
```
(Estética "lendária" — glow/headShake/NumberFlow — chega com a stack D8 na Fase D; aqui só tokens + CSS.)

### C4.7 i18n — `i18n/locale/{pt_BR,en}/chatlist.json` (ASSIGNEE_TYPE_TABS, linhas 22-26)
- `"ai"`: pt `"IA"` / en `"AI"`.
- `"AI_BADGE"` (novo, usado pelo card C3.5): pt `"IA"` / en `"AI"`.
- **Copy fix D-5**: pt_BR `"all": "Todos"` → `"Todas"` (conversas). Afeta o modo Clássico também →
  listado em OQ-4.

### C4.8 Specs
- `spec/finders/conversation_finder_spec.rb` (aditivo): com flag ON — `assignee_type='ai'` filtra só
  espelho captain; `unassigned` exclui IA; `ai_count`/`unassigned_count` corretos; com flag OFF —
  `unassigned` e counts intactos (IA conta como não-atribuída), `ai_count` presente mesmo assim; bot
  webhook atribuído não conta como IA.
- Vitest: `conversationStats` (guard `ai_count`), `assigneeTabItems` (flag OFF = 3 tabs atuais; ON =
  Minhas/IA/Todas; condicional aparece só com count>0; some IA sem assistants; unattended intacto),
  fallback de tab ativa, `ChatTypeTabs` aplica `.tab-alert`.

---

## 7. C5 — Automation action `assign_ai_agent` + macro (backend: Lote B2 / front: Lote F4)

### C5.1 `enterprise/app/models/enterprise/automation_rule.rb:6-8`
```ruby
def actions_attributes
  super + %w[add_sla assign_ai_agent]
end
```

### C5.2 `enterprise/app/services/enterprise/action_service.rb` (molde `add_sla`, 1-12)
```ruby
def assign_ai_agent(assistant_ids)
  return if assistant_ids.blank?

  assistant = @account.captain_assistants.find_by(id: assistant_ids.first)   # params chegam como ARRAY
  return if assistant.nil?
  # Elegibilidade (cobre o achado C8 no caminho in-process): IA só atua em inbox onde está registrada
  return unless @conversation.inbox.captain_assistants.exists?(assistant.id)

  mirror = assistant.mirror_agent_bot          # cria o espelho se faltar (Fase A)
  return if mirror.nil?

  # MESMO save: limpa humano + seta espelho (invariante; saves separados quebram com allow_auto_assign)
  Conversations::AssignmentService.new(
    conversation: @conversation, assignee_id: mirror.id, assignee_type: 'AgentBot'
  ).perform
  # after_commit da Fase A enfileira AssignmentKickJob → 1º turno pós-triagem de graça
end
```
No-op silencioso em tudo inválido (padrão `add_sla`). `AutomationRules::ActionService` faz
`@conversation.reload` entre actions (`action_service.rb:9-21`) — o método sempre opera no estado
fresco. **Ordem das actions**: `assign_ai_agent` ANTES de `assign_team` é segura (guard A2b); a ordem
inversa com team `allow_auto_assign` cria um humano intermediário (notificação/ruído) que a IA limpa em
seguida — comportamento conhecido, documentar na regra de triagem (sem reordenação automática no v1).

### C5.3 Macro NÃO herda de graça (provado: `add_sla` ausente de `Macro::ACTIONS_ATTRS`) — incluir, pois a narrativa §2 exige "agente comum devolve pra IA via macro"
- `app/models/macro.rb:33-35`: somar `assign_ai_agent` a `ACTIONS_ATTRS` (execução já herda o método —
  `Macros::ExecutionService < ActionService` + `include_mod_with`, `action_service.rb:113`).
- `app/javascript/dashboard/routes/dashboard/settings/macros/constants.js` (MACRO_ACTION_TYPES, após
  `assign_agent` linhas 7-11): `{ key: 'assign_ai_agent', label: 'ASSIGN_AI_AGENT', inputType:
  'search_select' }`.
- `app/javascript/dashboard/composables/useMacros.js:23-47` (`getMacroDropdownValues`): case
  `assign_ai_agent` → assistants `{id, name}` via `captainAssistants/getRecords`; +
  `MacroEditor.vue` (dispatch `captainAssistants/get` no mount, filtrar o action type se 0 assistants —
  mesmo padrão do C5.5).

### C5.4 Frontend automação
- `routes/dashboard/settings/automation/constants.js` (molde add_sla 717-721):
  `{ key: 'assign_ai_agent', label: 'ASSIGN_AI_AGENT', inputType: 'search_select' }`.
- `app/javascript/dashboard/helper/automationHelper.js:97-116` (`getActionOptions`): param novo
  `aiAgents` + `assign_ai_agent: aiAgents` no `actionsMap`.
- `app/javascript/dashboard/composables/useAutomationValues.js` (linha ~29): `const aiAgents =
  useMapGetter('captainAssistants/getRecords');` (assistants têm `{id, name}` — serve direto) e passar
  no call de `getActionOptions`.
- `routes/dashboard/settings/automation/AutomationRuleForm.vue:168-177` (`automationActionTypes`):
  esconder a action quando a conta não tem assistant (molde do filtro `add_sla`):
  ```js
  let actionTypes = isCloudFeatureEnabled('sla') ? AUTOMATION_ACTION_TYPES : ...;
  if (!aiAgents.value.length)
    actionTypes = actionTypes.filter(({ key }) => key !== 'assign_ai_agent');
  ```
- **Fetch**: a página de automação não busca assistants hoje — dispatch `captainAssistants/get` no
  `onMounted` do `AutomationRuleForm.vue` (dropdown nasceria vazio sem isso).

### C5.5 i18n
- `i18n/locale/{pt_BR,en}/automation.json` (molde ADD_SLA linha 155): `"ASSIGN_AI_AGENT"`: pt
  `"Atribuir agente IA"` / en `"Assign AI agent"`.
- `i18n/locale/{pt_BR,en}/macros.json`: `"ASSIGN_AI_AGENT"`: idem (verificar a árvore exata de chaves do
  arquivo — labels resolvem por `MACROS.ACTIONS.*` ou equivalente — na implementação).

### C5.6 Specs
- `spec/enterprise/services/enterprise/action_service_spec.rb` (novo ou aditivo): atribui espelho do
  assistant elegível limpando humano no mesmo save; no-op com id inválido / assistant de outra conta /
  inbox não-elegível; cria espelho on-demand; enfileira `AssignmentKickJob`.
- `spec/enterprise/models/automation_rule_spec.rb` + `spec/models/macro_spec.rb` (aditivos): whitelist
  aceita `assign_ai_agent`.
- Ordem team×IA: spec de integração — regra `[assign_ai_agent, assign_team(allow_auto_assign)]` termina
  com espelho dono e `assignee_id` nil (guard A2b).
- Vitest: `automationHelper` mapeia `assign_ai_agent` → lista de assistants.

---

## 8. C6 — HandoffTool com `team_id` (Lote B2)

**Arquivo:** `enterprise/lib/captain/tools/handoff_tool.rb` (estado pós-Fase A acima; TODO nas linhas
82-93 já desenha o param).

### C6.1 Param + descrição dinâmica
```ruby
param :team_id, type: 'string', desc: 'ID of the team to route the conversation to (optional)', required: false

# RubyLLM::Tool delega description da instância para a classe — override de instância enumera os
# times da conta (tools são instanciadas a cada run: assistant.agent → agent_tools → .new(self)).
def description
  teams = @assistant.account.teams.order(:id).map { |t| "#{t.id}: #{t.name}" }.join('; ')
  base = self.class.description
  teams.present? ? "#{base}. Available teams (id: name) — #{teams}" : base.to_s
end
```

### C6.2 `perform`/`trigger_handoff`
```ruby
def perform(tool_context, reason: nil, team_id: nil)
  ...
  trigger_handoff(conversation, reason, team_id)
  ...
end

def trigger_handoff(conversation, reason, team_id = nil)
  # (nota privada do reason — inalterado, linhas 26-37)
  conversation.bot_handoff!

  team = resolve_team(conversation, team_id)
  if team
    # UM update: solta o espelho E seta o time no MESMO save — com o espelho já nil em memória,
    # o guard A2b (assignment_handler.rb:13-21) libera o ensure_assignee_is_from_team, que
    # auto-atribui membro do time capacity-aware quando team.allow_auto_assign.
    conversation.update!(assignee_agent_bot_id: nil, team: team)
  elsif conversation.assignee_agent_bot&.captain?
    conversation.update!(assignee_agent_bot_id: nil)   # comportamento Fase A preservado
  end

  assign_to_available_agent(conversation)   # fallback: já tem guard `return if assignee_id.present?` (61)
  send_out_of_office_message_if_applicable(conversation)
end

def resolve_team(conversation, team_id)
  return nil if team_id.blank?
  conversation.account.teams.find_by(id: team_id)   # LLM pode alucinar id — validar SEMPRE na conta
end
```
- **"Manter dono quando a conversa já tem corretor"**: coberto pelo guard existente
  (`assign_to_available_agent` linha 61 — corrida humano-assumiu-no-meio). Sob exclusividade, IA dona ⇒
  `assignee_id` nil; "memória do corretor anterior" não existe no modelo e fica FORA do escopo C6
  (registrado; candidato a `custom_attributes` na Fase E se o uso pedir).
- `assign_to_available_agent` com team setado: restringir o round-robin fallback aos membros do time
  quando `conversation.team_id` presente (`member_ids & team.members.ids`), senão membros da inbox
  (comportamento atual).

### C6.3 Specs — `spec/enterprise/lib/captain/tools/handoff_tool_spec.rb` (aditivo; arquivo já mexido na Fase A)
team válido + allow_auto_assign → membro do time atribuído e espelho limpo num save; team inválido/de
outra conta → fallback round-robin; team sem allow_auto_assign → round-robin restrito ao time; conversa
já com humano → dono mantido; description enumera os times.

---

## 9. C7 — Tool `transferir_para_agente` (IA→IA) (Lote B2)

### C7.1 Registro — `config/agents/tools.yml` (molde handoff, linhas 43-46)
```yaml
- id: transferir_para_agente
  title: 'Transferir para outro Agente IA'
  description: 'Transfere a conversa para outro agente IA da conta (especialidade diferente)'
  icon: 'arrow-swap'
```
(id PT segue o precedente `buscar_imovel`; classe resolvida por convenção
`Captain::Tools::TransferirParaAgenteTool` — `captain_tools_helpers.rb:24-27`.)

### C7.2 NOVO `enterprise/lib/captain/tools/transferir_para_agente_tool.rb`
```ruby
class Captain::Tools::TransferirParaAgenteTool < Captain::Tools::BasePublicTool
  description 'Transfer this conversation to another AI agent better suited for the topic. ' \
              'Do NOT write any message after calling this tool — the new agent takes over silently.'
  param :assistant_id, type: 'string', desc: 'ID of the target AI agent'
  param :reason, type: 'string', desc: 'Why the conversation is being transferred (optional)', required: false

  # Enumera os assistants da conta na instanciação (a cada run — lista sempre fresca).
  # Elegibilidade por inbox é re-validada no perform (a inbox só é conhecida no runtime).
  def description
    others = @assistant.account.captain_assistants.where.not(id: @assistant.id)
                       .map { |a| "#{a.id}: #{a.name} — #{a.description}" }.join('; ')
    "#{self.class.description} Available agents (id: name — specialty): #{others}"
  end

  def perform(tool_context, assistant_id:, reason: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    target = conversation.account.captain_assistants.find_by(id: assistant_id)
    return 'Assistant not found' unless target
    return 'Cannot transfer to self' if target.id == @assistant.id
    return 'Assistant is not eligible for this inbox' unless conversation.inbox.captain_assistants.exists?(target.id)

    mirror = target.mirror_agent_bot
    return 'Assistant unavailable' if mirror.nil?

    log_tool_usage('transfer_to_agent', { conversation_id: conversation.id,
                                          from: @assistant.id, to: target.id, reason: reason })

    # Nota privada de auditoria (mesmo padrão do reason do handoff) — opcional, recomendada
    create_transfer_note(conversation, target, reason) if reason.present?

    # AssignmentService (NUNCA update_columns): limpa humano + seta espelho num save;
    # o after_commit da Fase A enfileira AssignmentKickJob → a NOVA IA responde o incoming
    # pendente imediatamente, com a knowledge dela (DC-7). A fala pós-tool da IA antiga é
    # dropada pelo re-check captain_can_respond? — desejado.
    Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: mirror.id, assignee_type: 'AgentBot'
    ).perform

    "Conversation transferred to #{target.name}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to transfer conversation'
  end

  private

  def create_transfer_note(conversation, target, reason)
    conversation.messages.create!(
      message_type: :outgoing, private: true, sender: @assistant,
      account: conversation.account, inbox: conversation.inbox,
      content: "Transferido para #{target.name}: #{reason}"
    )
  end
end
```
Nota privada NÃO afeta o kick (`last&.incoming?` olha mensagens visíveis — confirmar o scope do
`AssignmentKickJob` na implementação; se considerar privadas, criar a nota ANTES da troca).

### C7.3 Armar a tool — `enterprise/app/models/captain/assistant.rb:132-143` (`agent_tools`)
```ruby
def agent_tools
  tools = [
    self.class.resolve_tool_class('faq_lookup').new(self),
    self.class.resolve_tool_class('handoff').new(self)
  ]
  # IA→IA só faz sentido com 2+ assistants na conta (instanciação por run; exists? é barato)
  if account.captain_assistants.where.not(id: id).exists? &&
     (transfer_tool = self.class.resolve_tool_class('transferir_para_agente'))
    tools << transfer_tool.new(self)
  end
  ...
end
```
(B3 — `config['tools']` do assistant — ainda não existe; quando a Fase B chegar, a tool migra para o
arsenal configurável sem mudança de interface.)

### C7.4 Gap AD-11/B4 (agent_name legado) — mitigação barata INCLUÍDA
**Gap aceito:** histórico com `agent_name` de outra IA (ou `scenario_X` legado) cai no agente default da
gem silenciosamente. **Mitigação barata** (custo ~3 linhas, vale o preço): em
`enterprise/app/jobs/captain/conversation/response_builder_job.rb` (~linhas 247-258, onde o histórico é
montado p/ a gem), **não-forward** de `agent_name` cujo valor não pertença ao assistant ATUAL — mensagens
de outra IA entram como histórico "do usuário assistant default" sem rotear persona:
```ruby
# mensagens de OUTRA IA (transferência C7) ou de cenário legado não podem rotear persona:
agent_name = nil unless agent_name == current_assistant_agent_name
```
Validação fina em homolog continua sendo B4 (Fase B é dona do arquivo de prompt; aqui é só o guard de
não-forward no histórico).

### C7.5 Specs — NOVO `spec/enterprise/lib/captain/tools/transferir_para_agente_tool_spec.rb`
transfere para elegível (espelho setado, humano limpo, kick enfileirado); rejeita: self, assistant de
outra conta, não-elegível à inbox; cria espelho on-demand; description enumera os outros assistants;
`agent_tools` arma a tool apenas com 2+ assistants. + aditivo em `response_builder_job_spec.rb`:
agent_name de outra IA não é forwardado.

---

## 10. C8 — Elegibilidade endurecida + trava estrutural (Lote B2)

### C8.1 `app/services/conversations/assignment_service.rb:36-38` (defesa em profundidade, no-op silencioso — padrão do service)
```ruby
def agent_bot
  @agent_bot ||= begin
    bot = AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
    bot = nil if bot&.captain? && !eligible_captain_bot?(bot)
    bot
  end
end

def eligible_captain_bot?(bot)
  conversation.inbox.captain_assistants.exists?(id: bot.captain_assistant_id)
end
```

### C8.2 `app/controllers/api/v1/accounts/conversations/assignments_controller.rb` (erro EXPLÍCITO p/ UI)
Em `set_agent` (15-25), após o guard 403:
```ruby
return render_captain_assignment_not_eligible if ineligible_captain_assignment?
```
```ruby
def ineligible_captain_assignment?
  return false unless agent_bot_assignment? && requested_agent_bot&.captain?

  !@conversation.inbox.captain_assistants.exists?(id: requested_agent_bot.captain_assistant_id)
end

def render_captain_assignment_not_eligible
  render json: { error: I18n.t('conversations.captain.assignment_not_eligible') }, status: :unprocessable_entity
end
```
(chave i18n criada no F0.6; o dropdown C2 já filtra por `inbox_ids`, então o 422 é cinto de segurança
para API direta/corrida de elegibilidade.)

### C8.3 Spec-trava (espelho NUNCA em assignable_agents/round-robin) — `spec/models/inbox_spec.rb` + `spec/services/auto_assignment/agent_assignment_service_spec.rb` (aditivos)
- `inbox.assignable_agents` não inclui espelho captain (estrutural: é relação de `User`).
- Round-robin (`AutoAssignment::AgentAssignmentService`) com espelho "infiltrado" em allowed_ids não o
  atribui.
- `assignments_controller_spec.rb` (aditivo): admin + espelho NÃO-elegível → 422 `assignment_not_eligible`;
  admin + elegível → 200; in-process (service) com não-elegível → no-op nil.

---

## 11. C9 — Remover "None" da atribuição manual quando flag ON (Lote F1)

**4 pontos de injeção** (o plano citava 3; o command bar é o 4º). API/automação intactas — os pontos são
arrays de options do frontend; `assignee_id: nil` continua aceito pelo backend (D-11).

### C9.1 `app/javascript/dashboard/composables/useAgentsList.js` (ponto único do sidebar + command bar)
Ler a flag DENTRO do computed (mantém reatividade; precedente de supressão:
`ConversationParticipant.vue:25` usa `useAgentsList(false)`):
```js
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
// dentro de useAgentsList():
const { isAssignmentGateEnabled } = useReplyAssignmentGate();
// linha 76-79:
const showNone = includeNoneAgent && isAgentSelected.value && !isAssignmentGateEnabled.value;
return [...(showNone ? [createNoneAgent()] : []), ...filteredAgentsByAvailability];
```

### C9.2 `app/javascript/dashboard/composables/commands/useConversationHotKeys.js:184-186`
`noneAgentOption` já vira `null` automaticamente (deriva de `agentsList`). Endurecer o consumidor: o
comando "Unassign agent" só entra na lista quando `noneAgentOption.value` existe (guard no builder dos
comandos — verificar o uso exato no arquivo e condicionar o spread).

### C9.3 `app/javascript/dashboard/components/widgets/conversation/contextMenu/Index.vue:185-197`
None hardcoded (`id: null`, `name: 'None'` SEM i18n). Forma final:
```js
// setup() novo no componente (Options API): expõe isAssignmentGateEnabled
assignableAgents() {
  const noneOption = this.isAssignmentGateEnabled ? [] : [{
    confirmed: true,
    name: this.$t('AGENT_MGMT.MULTI_SELECTOR.LIST.NONE'),   // de quebra, i18n-iza o hardcode
    id: null, role: 'agent', account_id: 0, email: 'None',
  }];
  return [...noneOption, ...this.filteredAgentOnAvailability];
}
```

### C9.4 `app/javascript/dashboard/components/widgets/conversation/conversationBulkActions/AgentSelector.vue:42-52`
Mesmo tratamento do C9.3 (None `id: null` hardcoded, só com query vazia). Submit converge em
`useBulkActions.onAssignAgent` — sem mudança lá.

### C9.5 Sem mudança de i18n (reusa `AGENT_MGMT.MULTI_SELECTOR.LIST.NONE` existente). "None" de TIME
(`ConversationAction.vue:82`, `TeamActions.vue:21`, hotkeys:171) está FORA do escopo D-11 (decisão fala
de agente) — não tocar.

### C9.6 Specs
Vitest: `useAgentsList` com flag ON não injeta None (e com OFF injeta — específico: só quando há
assignee); contextMenu/AgentSelector sem None com flag ON e com None i18n-izado com flag OFF; hotkeys
toleram `noneAgentOption === null`.

---

## 12. C10 — Vigia de órfãs (Lote B3)

Padrão completo: cron (`schedule.yml`) → scheduler fan-out por conta (scope SQL no settings) → job por
conta (janela em `last_activity_at`) — precedente exato do auto-resolve
(`schedule.yml:13-16` → `conversations_resolution_scheduler_job.rb:5-7` → `resolution_job`).

### C10.1 `config/schedule.yml` (entrada nova)
```yaml
# vigia de órfãs (D-12): contas com modo "Atribuição obrigatória" (reply_assignment_gate)
conversations_orphan_watch_job:
  cron: '*/5 * * * *'
  class: 'Account::OrphanConversationsWatchJob'
  queue: scheduled_jobs
```

### C10.2 NOVO `app/jobs/account/orphan_conversations_watch_job.rb`
```ruby
class Account::OrphanConversationsWatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_reply_assignment_gate.find_each(batch_size: 100) do |account|
      Conversations::OrphanRetriageJob.perform_later(account)
    end
  end
end
```

### C10.3 NOVO `app/jobs/conversations/orphan_retriage_job.rb`
```ruby
class Conversations::OrphanRetriageJob < ApplicationJob
  queue_as :low
  DEFAULT_RETRIAGE_AFTER_MINUTES = 15
  BATCH_LIMIT = 100

  def perform(account)
    threshold = retriage_after(account).minutes.ago
    # órfã = open + SEM humano + SEM espelho captain (os DOIS nils — scope :unassigned não basta;
    # janela em last_activity_at: cobre conversa que ficou órfã DEPOIS, ex. user deletado)
    account.conversations.open
           .where(assignee_id: nil).without_captain_assignee
           .where('conversations.last_activity_at < ?', threshold)
           .limit(BATCH_LIMIT)
           .each { |conversation| process_orphan(conversation, account) }
  end

  private

  def retriage_after(account)
    (account.orphan_retriage_after.presence || DEFAULT_RETRIAGE_AFTER_MINUTES).to_i
  end

  # 1 re-triagem + 1 notificação POR EPISÓDIO (DC-8): dedupe via additional_attributes;
  # episódio reseta quando há atividade nova depois do último alerta.
  def process_orphan(conversation, account)
    alerted_at = conversation.additional_attributes['orphan_alerted_at']
    return if alerted_at.present? && Time.zone.parse(alerted_at) >= conversation.last_activity_at

    retriage(conversation, account)
    return unless still_orphan?(conversation)

    notify_admins(conversation, account)
    conversation.update!(additional_attributes:
      conversation.additional_attributes.merge('orphan_alerted_at' => Time.current.iso8601))
  end

  # Re-execução DIRETA das regras de triagem (NUNCA re-dispatch de CONVERSATION_CREATED — acordaria
  # webhooks/notificações/relatórios). Filosofia do AssignmentKickJob: re-executa o entry com re-check.
  def retriage(conversation, account)
    account.automation_rules.where(event_name: 'conversation_created', active: true).find_each do |rule|
      conversation.reload
      break unless still_orphan?(conversation)
      next unless AutomationRules::ConditionsFilterService.new(rule, conversation, {}).perform

      AutomationRules::ActionService.new(rule, account, conversation).perform
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  def still_orphan?(conversation)
    conversation.reload
    conversation.open? && conversation.assignee_id.nil? &&
      !conversation.assignee_agent_bot&.captain?
  end

  # Precedente exato: SlaEvent#create_notifications (sla_event.rb:64-86)
  def notify_admins(conversation, account)
    account.administrators.each do |admin|
      NotificationBuilder.new(
        notification_type: 'conversation_orphaned',
        user: admin, account: account, primary_actor: conversation
      ).perform
    end
  end
end
```

### C10.4 `app/models/notification.rb`
- `NOTIFICATION_TYPES` (38-47): `conversation_orphaned: 9` (flags email_/push_ do NotificationSetting
  derivam sozinhos do enum; 8/31 posições usadas — sem risco de overflow).
- `notification_title_map` (132-140): `'conversation_orphaned' =>
  'notifications.notification_title.conversation_orphaned'` (i18n criada no F0.6).
- `PRIMARY_ACTORS` já contém `'Conversation'` (linha 56) — ok.
- **Sem default de subscription** em `account_user.rb`: in-app sempre criada (NotificationBuilder só
  filtra `conversation_creation`); email/push opt-in do admin. Registrado.

### C10.5 i18n frontend — `i18n/locale/{pt_BR,en}/inbox.json` (precedente SLA, en:26-28)
Chave de exibição da notificação `conversation_orphaned`: pt `"Conversa sem responsável"` / en
`"Conversation without owner"` (seguir a árvore exata do precedente SLA na implementação).

### C10.6 Specs
- NOVO `spec/jobs/account/orphan_conversations_watch_job_spec.rb`: fan-out só para contas com flag ON.
- NOVO `spec/jobs/conversations/orphan_retriage_job_spec.rb`: órfã real (2 nils, janela) re-triada;
  conversa da IA NÃO é órfã; humano atribuído não; janela respeita `orphan_retriage_after` (default 15);
  regra com match atribui e NÃO notifica; sem match → notifica admins 1x (dedupe no 2º tick); nova
  atividade reseta o episódio; rule action com erro não derruba o loop.
- `spec/configs/schedule_spec.rb` valida o yaml sozinho.

---

## 13. LOTES de implementação (arquivos ESTRITAMENTE disjuntos)

```
            ┌────────────────────────────────────────────────────────────┐
            │  F0 — fundação (sequencial, PRIMEIRO, ~½ dia)              │
            └──────┬─────────┬─────────┬─────────┬─────────┬─────────────┘
                   ▼         ▼         ▼         ▼         ▼         ▼
                  B1        B2        F1        F2        F3        F4        B3
              (finder)  (autom/tools) (sidebar) (settings) (tabs)  (autom-front) (vigia)
                   └───── TODOS PARALELOS entre si — zero arquivo em comum ─────┘
```

| Lote | Tarefas | Arquivos (exclusivos do lote) |
|---|---|---|
| **F0 fundação** | flag DC-1, payload assistant DC-2, locales backend | `app/models/account.rb` · `app/controllers/api/v1/accounts_controller.rb` · `enterprise/app/views/api/v1/models/captain/_assistant.json.jbuilder` · `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` · NOVO `composables/useReplyAssignmentGate.js` (+spec) · `config/locales/en.yml` · `config/locales/pt_BR.yml` · `spec/models/account_spec.rb` · `spec/enterprise/controllers/.../captain/assistants_controller_spec.rb` |
| **B1 backend-finder** | C3 backend + C4 counts | `app/models/conversation.rb` · `app/finders/conversation_finder.rb` · `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` · `app/views/api/v1/models/_agent_bot_slim.json.jbuilder` · `app/views/api/v1/accounts/conversations/meta.json.jbuilder` · `.../index.json.jbuilder` · `spec/finders/conversation_finder_spec.rb` · `spec/models/conversation_spec.rb` · `spec/controllers/api/v1/accounts/conversations_controller_spec.rb` |
| **B2 backend-automation-tools** | C5 back, C6, C7, C8 | `enterprise/app/models/enterprise/automation_rule.rb` · `enterprise/app/services/enterprise/action_service.rb` · `app/models/macro.rb` · `enterprise/lib/captain/tools/handoff_tool.rb` · NOVO `enterprise/lib/captain/tools/transferir_para_agente_tool.rb` · `config/agents/tools.yml` · `enterprise/app/models/captain/assistant.rb` · `enterprise/app/jobs/captain/conversation/response_builder_job.rb` · `app/services/conversations/assignment_service.rb` · `app/controllers/api/v1/accounts/conversations/assignments_controller.rb` · specs: `enterprise/action_service` (novo), `transferir_para_agente_tool` (novo), `handoff_tool_spec`, `automation_rule_spec`, `macro_spec`, `assignments_controller_spec`, `inbox_spec`, `agent_assignment_service_spec`, `response_builder_job_spec` |
| **F1 front-sidebar** | C2 + C9 | `routes/dashboard/conversation/ConversationAction.vue` · `api/inbox/conversation.js` · `store/modules/conversations/actions.js` · `composables/useAgentsList.js` · `composables/commands/useConversationHotKeys.js` · `components/widgets/conversation/contextMenu/Index.vue` · `components/widgets/conversation/conversationBulkActions/AgentSelector.vue` · `i18n/locale/{pt_BR,en}/conversation.json` · vitest specs respectivos |
| **F2 front-settings** | C1 | `routes/dashboard/settings/agents/Index.vue` · NOVO `routes/dashboard/settings/agents/AIAgentsSection.vue` (+spec) · `i18n/locale/{pt_BR,en}/agentMgmt.json` |
| **F3 front-tabs-cards** | C3 front + C4 | `constants/globals.js` · `constants/permissions.js` · `components/ChatList.vue` · `components/widgets/ChatTypeTabs.vue` · `store/modules/conversations/getters.js` · `store/modules/conversationStats.js` · `components/widgets/conversation/ConversationCard.vue` · `i18n/locale/{pt_BR,en}/chatlist.json` · vitest specs respectivos |
| **F4 front-automation** | C5 front (+macro front) | `routes/dashboard/settings/automation/constants.js` · `routes/dashboard/settings/automation/AutomationRuleForm.vue` · `helper/automationHelper.js` · `composables/useAutomationValues.js` · `routes/dashboard/settings/macros/constants.js` · `routes/dashboard/settings/macros/MacroEditor.vue` · `composables/useMacros.js` · `i18n/locale/{pt_BR,en}/automation.json` · `i18n/locale/{pt_BR,en}/macros.json` · vitest `automationHelper.spec` |
| **B3 vigia** | C10 | `config/schedule.yml` · NOVO `app/jobs/account/orphan_conversations_watch_job.rb` · NOVO `app/jobs/conversations/orphan_retriage_job.rb` · `app/models/notification.rb` · `i18n/locale/{pt_BR,en}/inbox.json` · specs novos dos 2 jobs |

**Dependências:**
- **F0 → todos** (flag/scope usados por B1/B3/F1/F3; payload usado por F1/F2/F4; locales usados por B2).
- Entre os 7 lotes pós-F0: **nenhum arquivo em comum** (verificado item a item) → paralelismo total
  autorizado, sem worktree isolation.
- Dependências de RUNTIME (não de arquivo, não bloqueiam implementação — só o QA integrado): F3 valida
  contra B1 (`ai_count`/serializer); F1 valida contra B2 (422 elegibilidade); F4 valida contra B2
  (whitelist da action). B3 usa o scope `without_captain_assignee` criado em B1 (conversation.rb) —
  rodar specs do B3 **após** B1 estar no working tree (ou o dev do B3 stubba até lá).
- QA integrado (Playwright §14) somente com **todos** os lotes aplicados + `bundle exec rspec` da fase +
  vitest verdes.

**Riscos de execução por lote:**

| Risco | Lote | Mitigação |
|---|---|---|
| `assigned_count` derivado passa a incluir IA com flag ON | B1 | aceito/documentado (DC-4); spec congela a semântica |
| Payload de meta parcial zera `aiCount` | F3 | guard `'ai_count' in payload` (C4.5) + campo nas duas fontes (C4.2) |
| Tab condicional some enquanto ativa (`activeTabIndex=-1`) | F3 | watcher de fallback p/ "Minhas" (C4.4) |
| `captainAssistants/get` falha em conta sem Captain | F3/F1 | fetch gated pela flag (F3) / por isAdmin (F1); falha = lista vazia = UI se esconde |
| Dropdown C2 POSTar id de assistant (não espelho) → desatribuição silenciosa | F1 | options usam `agent_bot_id` (DC-2) + filtro `agent_bot_id` presente + spec |
| Ordem `assign_team` antes de `assign_ai_agent` cria humano intermediário | B2 | documentado na action; triagem oficial ordena IA→team; spec da ordem segura |
| Re-triagem do vigia repetir actions com side-effect | B3 | episódio único (dedupe `orphan_alerted_at`, DC-8) + spec |
| Espelho ausente (`agent_bot_id` nil) em assistants antigos | F0/F1 | rake `captain_mirrors` (Fase A) + filtro no front + `mirror_agent_bot` on-demand nos caminhos in-process |
| Conflito com Fase A no mesmo arquivo (`assignments_controller`, `assistant.rb`, `response_builder_job`) | B2 | mudanças aditivas; diff da Fase A já está no working tree — editar sobre ele, nunca reverter |

---

## 14. Validação da fase

### 14.1 Specs Rails (§5.1-C consolidado)
`finder/counts assignee_type='ai'` (flag ON/OFF) · serializer assignee-IA (3 variantes) · action
`assign_ai_agent` (elegibilidade, mesmo-save, kick) · macro whitelist · handoff team_id ·
transferir_para_agente (elegibilidade, kick, agent_name não-forward) · guard 422 não-elegível + no-op do
service · espelho fora de assignable_agents/round-robin (trava C8) · vigia (scheduler, janela, episódio,
notificação) · flag schema/default OFF.
Comando: `bundle exec rspec spec/finders spec/models/conversation_spec.rb spec/models/account_spec.rb
spec/models/macro_spec.rb spec/jobs/account spec/jobs/conversations spec/controllers/api/v1/accounts/conversations*
spec/enterprise` (+ vitest `npx vitest run` dos arquivos tocados).

### 14.2 Playwright (light + dark, user de teste DEDICADO — nunca resetar senha de conta real)
Pré-condição: como a UI do toggle só chega na Fase D (D7), ligar/desligar a flag via console:
`bundle exec rails runner "Account.find(ID).update!(reply_assignment_gate: true)"` (e `false`/`nil` para
o modo Clássico). Evidências (screenshots 2 temas) em `plano/evidencias/fase-c/`.

| # | Cenário | Passos | Aceite |
|---|---|---|---|
| **P3** | Página de usuários | Settings→Agentes; conta com 2 assistants | seção "Agentes IA" com avatar+badge+inboxes elegíveis, read-only (sem editar/deletar), 2 temas, sem i18n leak; some quando 0 assistants |
| **P4** | Sidebar admin vs agente | abrir mesma conversa com admin e com agente comum | seletor "Agente IA" SÓ para admin; lista só assistants elegíveis à inbox; atribuir → toast, sem reload, meta atualiza |
| **P5** | Tabs (flag ON) em conversas/time/label | ligar flag; navegar home/team/label | barra Minhas/IA/Todas; tab IA conta/filtra só conversas de espelho captain; contador atualiza ao vivo (atribuir IA → `aiCount`+1 via websocket/meta); "Não atribuídas" AUSENTE com count=0. Flag OFF: 3 tabs atuais intactas (P13 antecipado: layout Clássico intacto) |
| **P5b** | Órfã de propósito | flag ON; criar conversa sem atribuição | tab condicional "Não atribuídas" APARECE com estilo alerta (tokens ruby, 2 temas); atribuir a órfã → tab some e a ativa cai em "Minhas" sem erro de console; (vigia: validar por spec + execução manual do job — cron 5min não entra no Playwright) |
| **P5c** | Dropdowns sem "None" | flag ON; sidebar, context menu da lista, bulk actions, Cmd+K | opção "None"/"Nenhum" inexistente nos 4; flag OFF: None volta (e i18n-izado no context menu/bulk) |
| **P6** | Card da IA | conversa atribuída à IA | badge "IA" + nome/ícone bot no card; conversa listada na tab "IA"; em "Todas" o assignee mostra a IA; NÃO aparece em "Não atribuídas" (flag ON) |
| **P12** | DOM walker pós-mudanças | varrer telas tocadas | sem chave i18n vazada, ícones com width/height>0, sem console errors, contraste ok nos 2 temas |

### 14.3 Aceite da fase (espelha §4 do consolidado)
Admin atribui IA pela UI e agente comum nem vê o seletor; card mostra a IA como dona com badge; barra
Minhas/IA/Todas conta/filtra certo em todas as views; órfã proposital materializa a tab condicional e o
vigia re-triagem+notifica (spec/manual); dropdowns sem None (flag ON); automação
label→`assign_ai_agent`(+`assign_team`) funciona com invariante preservada; handoff IA→corretor com
team; transferência IA→IA responde com a knowledge do novo; seção "Agentes IA" ok nos 2 temas; **flag
OFF: TUDO como hoje**.

---

## 15. openQuestions (contradições com D-1..D-13 — NÃO resolvidas aqui)

- **OQ-1 (D-5):** D-5 define a tab IA como "conversas com `assignee_agent_bot_id` presente"; o design
  restringe a **espelhos captain** (`bot_type=1`) — bot webhook atribuído via coluna NÃO conta como IA e
  continua contando como não-atribuída. Refinamento técnico que diverge da letra de D-5; sancionar.
- **OQ-2 (D-5):** "tab IA em TODAS as listas" — exceções operacionais do design: (a) a view
  "unattended" mantém as 3 tabs clássicas (não existem counts unattended-por-IA no SQL); (b) custom
  views/folders e busca não renderizam a barra de tabs hoje (comportamento pré-existente do produto,
  `ChatList.vue:1212`). Sancionar as duas exceções.
- **OQ-3 (D-13/D-3):** o seletor "Agente IA" do sidebar (C2) fica visível para admin **mesmo com a flag
  OFF** (modo Clássico) — D-13 diz "Clássico = tudo como hoje", mas escondê-lo impediria pilotar a IA
  antes da virada (e D-3 não condiciona à flag). Design adotou: visível sempre que a conta tem assistant
  elegível à inbox (DC-5). Sancionar ou condicionar à flag.
- **OQ-4 (D-13/D-5):** o copy pt_BR da tab "all" muda de "Todos" para "Todas" (D-5) **globalmente** —
  visível também no modo Clássico, contrariando a letra "com a flag desligada, tabs atuais intactas" de
  D-13. Idem para o badge "IA" no card (aparece também com flag OFF se houver conversa atribuída à IA) e
  o fix de colisão id User×Bot em `getMineChats` (correção de bug válida nos dois modos). A lista local
  de "Não atribuídas" permanece consistente com o backend nos dois modos (getter gated, C3.4). Sancionar
  esses 3 vazamentos benignos para o modo Clássico.
