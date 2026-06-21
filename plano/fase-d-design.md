# Fases D + E — Design Executável (Gate universal de resposta + Políticas e limpeza)

> **@architect (AIOX) — 2026-06-11.** Baseado em `plano/ia-consolidado.md` (§1 D-4/D-9/D-13, §4 Fases D/E
> + aceites, §5.1-D, §5.2 P7-P13, §9-10) + dossiê `/tmp/fase-d-e-exploracao.json` (5 clusters) +
> `plano/fase-c-design.md` (alinhamento de superfícies compartilhadas). Citações arquivo:linha
> **re-verificadas no código real em 11/06 ~23h UTC** (HEAD `c69979876`).
>
> **Regras inegociáveis:** working tree only (zero commit); components-next para UI nova; tokens
> `n-*`/`rgb(var(--token))` — **NUNCA `var(--n-*)`**, nunca hex hardcoded; i18n pt_BR + en em paridade;
> dark mode; `prefers-reduced-motion` respeitado em TODO efeito; Playwright light+dark obrigatório.
>
> **Coordenação com humano ativo:** Paulo está commitando no repo (B3 = `c69979876`). NENHUM lote desta
> fase edita `enterprise/app/models/captain/assistant.rb` nem tools captain EXISTENTES
> (`enterprise/lib/captain/tools/*` já criados). Arquivos novos em enterprise são permitidos.
> ReplyBox / messages_controller / notification / settings são superfícies livres.

---

## 0. Premissas (estado verificado do repo)

| Fato | Evidência |
|---|---|
| Fases 0+A **commitadas** (`2bee0f724`); B3 commitado por Paulo (`c69979876` — `config['tools']` arma tools de negócio) | `git log` |
| APIs da Fase A disponíveis: espelho captain (`agent_bot.bot_type: :captain`, `captain_assistant_id`), gate por atribuição, `AssignmentKickJob` (A2d), release no resolve (A2e), release no reply humano (A2c), guard 403 admin-only, `conversation.assignee_type`/`assigned_entity` | `app/models/agent_bot.rb:43-48`, `app/models/conversation.rb:237-246`, `enterprise/app/models/enterprise/concerns/conversation.rb:14-37`, `enterprise/app/models/enterprise/message.rb:38-47` |
| Fase C está **em design** (`plano/fase-c-design.md`), implementação pendente. A Fase D **depende** dela em pontos nomeados (abaixo) | working tree sem mudanças de app |
| Flag `reply_assignment_gate` vive em **`account.settings` jsonb** (bigint `feature_flags` está cheio: 66/63). Criada pela Fase C (C-F0): schema + `store_accessor` + helper `Account#reply_assignment_gate_enabled?` + whitelist em `accounts_controller#permitted_settings_attributes` + composable `useReplyAssignmentGate()`. **A sugestão do cluster guard de usar `features.yml` está DESCARTADA** | `fase-c-design.md` DC-1/F0 |
| Frontend lê a flag por `useReplyAssignmentGate()` (fonte única: `currentAccount.settings.reply_assignment_gate`) | `fase-c-design.md` F0.5 |
| Índice `uniq_primary_actor_per_account_notifications` **NÃO é unique** (apesar do nome); `RemoveDuplicateNotificationJob` dedupe por `(user_id, primary_actor_id)` — notificar dois usuários diferentes pela mesma conversa é seguro (risco do dossiê RESOLVIDO) | `db/schema.rb:1347`, `app/jobs/notification/remove_duplicate_notification_job.rb`, `app/models/notification.rb:208` |
| `createPendingMessageAndSend` dispara `sendMessageWithData` **SEM await** — hoje o 422 nunca chega ao catch do ReplyBox; vira bolha FAILED + unhandled rejection | `store/modules/conversations/actions.js:405-408` |
| Não existe mutation que remova UMA mensagem do thread (`DELETE_MESSAGE` declarado em `mutation-types.js:46` mas **sem implementação**) — D6 cria uma | `store/modules/conversations/index.js` (grep) |
| Stack D8: versões confirmadas compatíveis (motion-v 2.3.0 / @number-flow/vue 0.5.0 / @formkit/auto-animate 0.9.0 / canvas-confetti 1.9.4 / tailwindcss-animated 2.1.0; vue 3.5.12, @vueuse 12, tailwind 3.4.19, pnpm 10.2.0). `shake`/`wiggle` do fork em `theme.keyframes` **top-level** colidem com classes homônimas do plugin (fork vence — plugin mascarado nessas duas) | `package.json:65,110,160,193`, `tailwind.config.js:245-330` |

### O que a Fase D consome da Fase C (dependências nomeadas)

| Peça da C | Usada por | Sem ela |
|---|---|---|
| C-F0: helper `reply_assignment_gate_enabled?` + composable + whitelist do setting | D1, D3, D4, D7 | D-L1/L3/L4 não compilam — **C-F0 é pré-requisito duro da onda D-1** |
| C-F1: `conversation.json` (chaves AI_AGENT) + `actions.js` (assignAIAgent) | D-L2 (mesmos arquivos) | conflito de merge — D-L2 só na onda D-2 |
| C-B1 (DC-3): serializer `meta.assignee.type === 'agent_bot'` | D2 variante (c) | dialog não distingue "dona IA" de "sem dono" — variante (c) degrada para (a) com texto errado |
| C-B3: `notification.rb` com `conversation_orphaned: 9` | D-L3 (mesmo arquivo) | D4 usa o valor **10** e deixa o 9 reservado (gap de enum é inofensivo) |
| C-F3: `ChatList.vue`/`ChatTypeTabs.vue` (tabs IA/alerta) | D-L7 (efeitos nas tabs) | D-L7 só na onda D-2 |

---

## 1. Decisões de design da fase (DD-x) — incorporam o brief, NÃO rediscutem

- **DD-1 (D1):** guard **controller-level** no `messages_controller` cobrindo `create` + `share_location` +
  `share_contact` (cobre macros/campanhas/jobs de graça — eles não passam pelo controller). Bypasses:
  `params[:private].to_s == 'true'` (padrão do fork, :264), `!user.is_a?(User)` (bot-token/nil),
  `params[:source_id].present?` (echo do app WAHA externo; dashboard nunca envia source_id no create),
  `message_type == 'incoming'`. **Admin NÃO tem bypass** (D-4: admin também assume via variante d).
- **DD-2 (D1):** primeira mensagem em `conversations_controller#create` → **self-assign automático do
  criador** quando gate ON (proposta; ver OQ-D1). 422 ali seria UX quebrada (o dialog não existe no
  modal de nova conversa) e bypass puro abriria furo no "só o assignee responde".
- **DD-3 (D2):** interceptar em `onSendReply` (ReplyBox.vue:1488) **ANTES** de `confirmOnSendReply`
  (:1354) — draft intacto (`clearMessage()` só roda em :1389); precedente exato do confirm de variáveis
  indefinidas (:1515-1518). Pós-confirmação: re-invocar `onSendReply()` (o assignee já é o usuário →
  gate passa → envio automático), com one-shot anti-loop.
- **DD-4 (D2):** bypass de nota usa **`this.isPrivate`** (payload, :329-338), não só `isOnPrivateNote`
  (:517) — cobre a nota FORÇADA de canal sem `can_reply` (risco do dossiê). Estende a decisão do brief
  sem contradizê-la: tudo que será gravado como `private: true` passa sem dialog.
- **DD-5 (D2):** conversa **sem time** + usuário com 2+ times → variante (a) ganha um select de time
  (dos times DO usuário, pré-selecionado quando há 1 só) — precedente do próprio fork
  (`ReplyBoxBanner.onClickSelfAssign` força `TeamSelectionModal` quando `!conversationHasTeam`,
  :147-153) e `team_required_for_resolution` (conversation.rb) exigiria o time logo adiante. 0 times →
  self-assign puro.
- **DD-6 (D4):** tipo NOVO `conversation_unassignment: 10` (9 fica reservado para `conversation_orphaned`
  da C10). **Sem migration** (coluna integer; NUNCA renumerar — bits do NotificationSetting derivam do
  valor). Caminho novo no listener **fora** do guard `notifiable_assignee_change` (que é `false` em
  self-assign — exatamente o roubo D-9). Notifica `old` quando `old≠new`, `old≠Current.user` e
  `new.present?` (desatribuição para o limbo é assunto do vigia C10, não de "takeover").
- **DD-7 (D4):** a notificação ao anterior é **gated pela flag** (`account.reply_assignment_gate_enabled?`)
  — D-13 manda o Clássico ficar intacto (ver OQ-D2).
- **DD-8 (D6):** o 422 `assignment_required` passa a **propagar** (`return dispatch(...)` em
  `createPendingMessageAndSend`) e a bolha FAILED é **suprimida** para esse error_code (mutation nova
  `REMOVE_PENDING_MESSAGE` remove a bolha PROGRESS já commitada). Payloads que falharam ficam numa fila
  no ReplyBox e são reenviados na ordem após o usuário confirmar o dialog (cobre multi-part N×422 com
  dedupe de dialog).
- **DD-9 (D7):** toggle = card "Modo de atendimento" em Configurações da conta (rota já admin-only,
  `account.routes.js:10`), molde `DashboardKpiStrip` (SectionLayout + `useAccount().updateAccount`),
  confirmação via Dialog components-next. Persiste em `settings.reply_assignment_gate` (whitelist da
  C-F0). Reatividade: `update.json.jbuilder` re-renderiza o partial completo da account → todas as
  superfícies (tabs C4, None C9, dialog D2, banner D3, guard via backend) reagem sem reload (P13).
- **DD-10 (D8):** instalar via `pnpm add`; **só usar classes do plugin sem colisão**
  (`animate-jump-in`, `animate-fade-up`); keyframes novos (`head-shake`, `glow-pulse`) entram em
  `theme.keyframes`/`theme.animation` **top-level** (padrão do fork, NUNCA em extend); componentes
  portados do Inspira em `components-next/effects/` com tokens `rgb(var(--token))`;
  `MotionConfig reducedMotion="user"` global no `dashboard/App.vue`; confetti SEMPRE lazy
  (`await import()`, molde `ensureLeaflet`, LocationPickerModal.vue:86-95) com
  `disableForReducedMotion: true`.
- **DD-11 (E4):** `AssistantLog.event_type` é STRING com whitelist no modelo — ampliar `EVENT_TYPES` +
  watcher `after_commit` enterprise sobre `saved_change_to_assignee_agent_bot_id` (o assistant do
  release é capturado pelo **valor antigo** do saved_change — `captain_assistant_id` é NOT NULL).
  Nenhuma referência a Captain entra no core.
- **DD-12 (E2):** padronizar APENAS os call-sites reais: `consolida_conversas_duplicadas.rb:60-62`
  (único que QUEBRA a invariante), `disparo_lead_job.rb:127` (padronização), e **documentar**
  `agents/destroy_job.rb:41` (órfãs sem evento — mitigação é o vigia C10).
- **DD-13 (i18n compartilhado — UM dono por onda):** `conversation.json` → onda C: C-F1; onda D: D-L2.
  `config/locales/{en,pt_BR}.yml` → onda C: C-F0; onda D: **D-L1** (escreve TAMBÉM as chaves do D4,
  contrato definido pelo D-L3). `generalSettings.json` + `settings.json` + `profile/constants.js` →
  **D-L4** (escreve TAMBÉM o TYPE_LABEL do D4). `notification.rb` → onda C: C-B3; onda D: D-L3.

---

## 2. D1 — Guard backend `assignment_required` (Lote D-L1)

### 2.1 `app/controllers/api/v1/accounts/conversations/messages_controller.rb`

`create` em :44-55, `share_location` em :106, `share_contact` em :152. Adicionar no topo da classe:

```ruby
before_action :enforce_reply_assignment_gate, only: [:create, :share_location, :share_contact]
```

E nos métodos privados (junto de `message_finder`, :204):

```ruby
# D1 (D-4): com o "Modo atribuição obrigatória" ligado, só o assignee responde.
# Controller-level de propósito: macros/campanhas/scheduled/IA criam via jobs e
# nunca passam aqui; private_chat tem controller próprio (fora do gate).
def enforce_reply_assignment_gate
  return unless Current.account.reply_assignment_gate_enabled?     # helper da Fase C (C-F0)

  user = Current.user || @resource
  return unless user.is_a?(User)                       # bot-token (AgentBot) e nil ficam fora
  return if params[:private].to_s == 'true'            # nota privada — padrão do fork (:264)
  return if params[:source_id].present?                # echo do app WAHA externo (User real id=1)
  return if params[:message_type].to_s == 'incoming'   # incoming via API não é resposta de agente
  return if @conversation.assignee_id == user.id

  render_assignment_required
end

def render_assignment_required
  assignee = @conversation.assigned_entity              # assignee_agent_bot || assignee (Fase A)
  render json: {
    error: I18n.t('conversations.reply_assignment_gate.assignment_required'),
    error_code: 'assignment_required',
    meta: {
      current_assignee: assignee && {
        id: assignee.id,
        name: assignee.try(:available_name) || assignee.name,
        type: @conversation.assignee_type               # 'AgentBot' | 'User' | nil
      },
      team: @conversation.team && { id: @conversation.team.id, name: @conversation.team.name }
    }
  }, status: :unprocessable_entity
end
```

Notas de forma:
- A chave **`error` é mantida** além de `error_code`/`meta` — o alert de fallback do front só lê
  `data.error` (risco do dossiê sobre o formato divergente do `render_record_invalid`).
- O `before_action` roda APÓS os callbacks do BaseController (`@conversation` já setada) e ANTES das
  supressões WAHA do `create` — echoes têm `source_id`, então passam pelo bypass antes de chegar lá.
- `share_location`/`share_contact` criam outgoing direto (`messages.create!`, :113-130/:163-180) — o
  mesmo `before_action` cobre os três.
- Caminhos documentados FORA do guard (decisão, não esquecimento): `private_chat/messages_controller`
  (feature interna), widget/public API (só incoming de Contact), jobs (macro/campanha/scheduled/captain
  — `conversation.messages.create!` direto), `copilot` quando insere no reply box (vira create normal →
  guard pega, desejado).

### 2.2 `app/controllers/api/v1/accounts/conversations_controller.rb:47-52` (DD-2 / OQ-D1)

```ruby
def create
  ActiveRecord::Base.transaction do
    @conversation = ConversationBuilder.new(params: params, contact_inbox: @contact_inbox).perform
    self_assign_creator_for_reply_gate if params[:message].present?
    Messages::MessageBuilder.new(Current.user, @conversation, params[:message]).perform if params[:message].present?
  end
end

# D1/DD-2: gate ON + conversa nova criada já com mensagem do criador e sem dono explícito
# → self-assign automático (422 aqui quebraria o modal de nova conversa; bypass abriria furo).
def self_assign_creator_for_reply_gate
  return unless Current.account.reply_assignment_gate_enabled?
  return unless Current.user.is_a?(User)
  return if @conversation.assignee_id.present?

  @conversation.update!(assignee_id: Current.user.id)   # callbacks rodam; self-assign não notifica
end
```

### 2.3 i18n backend — `config/locales/en.yml` + `config/locales/pt_BR.yml` (D-L1 é o dono na onda D; inclui as chaves do D4 por contrato com D-L3)

Sob `conversations:` (en.yml ~:241 / pt_BR.yml ~:227):

```yaml
# en
reply_assignment_gate:
  assignment_required: "You must take over this conversation before replying"
# pt_BR
reply_assignment_gate:
  assignment_required: "Você precisa assumir a conversa antes de responder"
```

Sob `notifications.notification_title` (en.yml:231-238 / pt_BR.yml:217-224) — chave do D4:

```yaml
# en
conversation_unassignment: 'Conversation (#%{display_id}) was taken over by %{taker}'
# pt_BR
conversation_unassignment: 'A conversa (#%{display_id}) foi assumida por %{taker}'
```

### 2.4 Specs (D-L1)

`spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` (aditivo):
- flag OFF → não-assignee cria outgoing normalmente (Clássico intacto);
- flag ON: assignee cria (200); não-assignee → **422** com `error`, `error_code: 'assignment_required'`,
  `meta.current_assignee {id,name,type:'User'}`, `meta.team {id,name}`;
- dono = espelho captain → `meta.current_assignee.type == 'AgentBot'` e name do espelho;
- conversa sem dono → `meta.current_assignee` nil + team presente/nil;
- **admin não-assignee → 422** (sem bypass de role);
- bypasses: `private: 'true'` (string, multipart) passa; `source_id` presente passa (echo WAHA);
  bot-token (`Current.user` AgentBot) passa; `message_type: 'incoming'` passa;
- `share_location` e `share_contact`: 422 para não-dono, 200 para dono, nota… (não têm private — só dono);
- **interação A2c×D1 especificada**: com gate ON, POST de não-assignee é bloqueado ANTES de criar a
  Message → `release_captain_mirror_after_human_reply` NÃO roda → espelho permanece; echo externo
  (bypass `source_id`) cria a Message → A2c roda → espelho solta (comportamento esperado, OQ-D3).

`spec/controllers/api/v1/accounts/conversations_controller_spec.rb` (aditivo):
- gate ON + create com `message` → conversa nasce com `assignee_id == criador`; com `assignee_id`
  explícito nos params → respeitado (builder ganha); gate OFF → sem self-assign; sem `message` → sem
  self-assign;
- **carona E3**: request spec do `authorize_team_access` (:231, implementado na Fase 0/A SEM spec) —
  membro do time acessa, não-membro recebe 403 com payload i18n.

---

## 3. D2 — Dialog "Quer atribuir a você?" (Lote D-L2)

### 3.1 NOVO `app/javascript/dashboard/components-next/Conversation/AssignToReplyDialog.vue`

Script setup, embrulha o `Dialog` components-next (API imperativa `open()/close()`,
`dialog/Dialog.vue:88-114` — focus trap/ESC/a11y nativos). Forma final (esqueleto completo):

```vue
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { fireTakeoverConfetti } from 'dashboard/components-next/effects/useConfetti';

const emit = defineEmits(['confirm']);
const { t } = useI18n();
const store = useStore();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const myTeams = useMapGetter('teams/getMyTeams');       // is_member do backend (_team.json.jbuilder:6)
const allTeams = useMapGetter('teams/getTeams');

const dialogRef = ref(null);
const overrideMeta = ref(null);                          // meta do 422 (D6) — dono ATUALIZADO
const selectedTeamId = ref(null);
const isLoading = ref(false);
const errorMessage = ref('');

// ----- dono atual: prioridade para o meta do 422 (corrida P16), senão store -----
const assigneeInfo = computed(() => {
  if (overrideMeta.value) {
    const ca = overrideMeta.value.current_assignee;
    return ca ? { id: ca.id, name: ca.name, isAI: ca.type === 'AgentBot' } : null;
  }
  const a = currentChat.value?.meta?.assignee;
  return a ? { id: a.id, name: a.available_name || a.name, isAI: a.type === 'agent_bot' } : null;
});
const conversationTeam = computed(() =>
  overrideMeta.value?.team ?? currentChat.value?.meta?.team ??
  (currentChat.value?.team_id ? { id: currentChat.value.team_id } : null)
);

// fail-open quando o store de teams ainda não carregou (precedente ConversationAction.vue:206-208)
const isMemberOfConversationTeam = computed(() => {
  if (!conversationTeam.value) return true;
  if (!allTeams.value.length) return true;               // fail-open
  return myTeams.value.some(team => team.id === conversationTeam.value.id);
});

// ----- variantes (a)/(b)/(c)/(d) do plano -----
const variant = computed(() => {
  if (!isMemberOfConversationTeam.value) return 'd';     // fora do time (admin ou agente)
  if (assigneeInfo.value?.isAI) return 'c';              // dona IA
  if (assigneeInfo.value) return 'b';                    // dono humano (colega)
  return 'a';                                            // sem dono
});
// DD-5: variante (a/b/c) em conversa SEM time → select dos MEUS times (pré-seleciona se 1)
const needsTeamSelection = computed(
  () => variant.value === 'd' || (!conversationTeam.value && myTeams.value.length > 0)
);
const canConfirm = computed(() => !needsTeamSelection.value || Boolean(selectedTeamId.value));

const title = computed(() => t(`CONVERSATION.REPLY_GATE_DIALOG.TITLE.${variant.value.toUpperCase()}`,
  { name: assigneeInfo.value?.name || '' }));
const description = computed(() => t(`CONVERSATION.REPLY_GATE_DIALOG.DESC.${variant.value.toUpperCase()}`,
  { name: assigneeInfo.value?.name || '', team: conversationTeam.value?.name || '' }));
const confirmLabel = computed(() => {
  if (variant.value === 'd') return t('CONVERSATION.REPLY_GATE_DIALOG.CONFIRM.D');
  return t(`CONVERSATION.REPLY_GATE_DIALOG.CONFIRM.${variant.value.toUpperCase()}`,
    { name: assigneeInfo.value?.name || '' });
});

const show = (meta = null) => {
  overrideMeta.value = meta;
  errorMessage.value = '';
  if (needsTeamSelection.value && myTeams.value.length === 1)
    selectedTeamId.value = myTeams.value[0].id;
  dialogRef.value?.open();                               // idempotente (showModal já-aberto no-op)
};
const hide = () => dialogRef.value?.close();
defineExpose({ show, hide });

const onConfirm = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    if (needsTeamSelection.value && selectedTeamId.value) {
      await store.dispatch('assignTeam', {
        conversationId: currentChat.value.id, teamId: selectedTeamId.value, rethrow: true,
      });
    }
    await store.dispatch('assignAgent', {
      conversationId: currentChat.value.id, agentId: currentUser.value.id, rethrow: true,
    });
    fireTakeoverConfetti();                              // lazy, 1x/sessão, reduced-motion safe (D8)
    hide();
    emit('confirm');                                     // ReplyBox reenvia a mensagem
  } catch (error) {
    errorMessage.value = t('CONVERSATION.REPLY_GATE_DIALOG.ERROR');
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="title"
    :description="description"
    :confirm-button-label="confirmLabel"
    :cancel-button-label="$t('CONVERSATION.REPLY_GATE_DIALOG.CANCEL')"
    :is-loading="isLoading"
    :disable-confirm-button="!canConfirm || isLoading"
    @confirm="onConfirm"
  >
    <!-- conteúdo: card do dono atual (Avatar + nome + badge IA) -->
    <div v-if="assigneeInfo" class="flex items-center gap-3 rounded-lg bg-n-alpha-2 p-3">
      <Avatar :name="assigneeInfo.name" :size="32" hide-offline-status />
      <span class="text-body-main text-n-slate-12">{{ assigneeInfo.name }}</span>
      <span v-if="assigneeInfo.isAI"
            class="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium
                   bg-n-brand/10 text-n-brand">
        <span class="i-lucide-bot size-3" />{{ $t('CONVERSATION.REPLY_GATE_DIALOG.AI_BADGE') }}
      </span>
    </div>
    <!-- variante (d)/DD-5: select dos times DO usuário (NUNCA todos os times da conta) -->
    <div v-if="needsTeamSelection" class="flex flex-col gap-2 mt-3">
      <span class="text-sm text-n-slate-11">{{ $t('CONVERSATION.REPLY_GATE_DIALOG.TEAM_LABEL') }}</span>
      <label v-for="team in myTeams" :key="team.id"
             class="flex items-center gap-2 rounded-lg border p-3 cursor-pointer"
             :class="selectedTeamId === team.id ? 'border-n-brand bg-n-brand/5' : 'border-n-weak'">
        <input v-model="selectedTeamId" type="radio" :value="team.id" class="accent-n-brand" />
        <span class="text-body-main text-n-slate-12">{{ team.name }}</span>
      </label>
      <span v-if="!myTeams.length" class="text-sm text-n-slate-10">
        {{ $t('CONVERSATION.REPLY_GATE_DIALOG.NO_TEAMS') }}
      </span>
    </div>
    <span v-if="errorMessage" class="mt-2 text-sm text-n-ruby-11">{{ errorMessage }}</span>
  </Dialog>
</template>
```

Notas:
- Variante (d) com **0 times do usuário**: degrada para self-assign puro mantendo o time da conversa
  (`needsTeamSelection` exige `myTeams.length > 0`; texto NO_TEAMS explica). Backend aceita.
- **Animação (D8):** entrada slide-up/spring com motion-v SOBRE o conteúdo (wrapper interno
  `<m.div :initial="{ opacity: 0, y: 24 }" :animate="{ opacity: 1, y: 0 }"
  :transition="{ type: 'spring', visualDuration: 0.35, bounce: 0.25 }">` no slot default — o slot só
  renderiza com `isOpen` (Dialog.vue:146), então o mount anima a entrada; exit fica com o transition
  nativo). Import `m`/`LazyMotion`-compatível. **Gate de runtime:** se o pacote ainda não estiver
  instalado (D-L5), entregar primeiro com o wrapper CSS (`animate-fade-in-up` do fork) e trocar pelo
  spring na integração — comportamento idêntico, só a física muda.
- Sucesso: checkmark animado (`AnimatedCheckmark` de D-L6) é opcional/encantamento; confetti na 1ª
  assunção da sessão (sessionStorage) via `fireTakeoverConfetti` (lazy import; ver §8.3).

### 3.2 `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`

- **setup()**: somar `useReplyAssignmentGate()` (expor `isAssignmentGateEnabled`).
- **data**: `pendingGatePayloads: []`, `gateConfirmedOnce: false`.
- **computed** (perto de `isOnPrivateNote`, :517):

```js
shouldShowAssignmentGate() {
  if (!this.isAssignmentGateEnabled) return false;
  if (this.isPrivate) return false;                  // DD-4: payload private passa (nota + nota forçada)
  const assignee = this.currentChat?.meta?.assignee;
  if (!assignee) return true;                        // (a) sem dono
  if (assignee.type === 'agent_bot') return true;    // (c) dona IA (serializer C-B1/DC-3)
  return assignee.id !== this.currentUser.id;        // (b)/(d) colega ou fora do time
},
```

- **`onSendReply()` (:1488)** — inserir após os guards de áudio, ANTES do bloco de variáveis:

```js
if (this.shouldShowAssignmentGate && !this.gateConfirmedOnce) {
  this.$refs.assignToReplyDialog.show();
  return;                                            // draft intacto (this.message não foi tocado)
}
this.gateConfirmedOnce = false;
```

- **handler novo**:

```js
async onAssignmentGateConfirmed() {
  if (this.pendingGatePayloads.length) {             // caminho D6: draft já foi limpo, reenvia payloads
    const payloads = [...this.pendingGatePayloads];
    this.pendingGatePayloads = [];
    for (const payload of payloads) {
      // sequencial de propósito: preserva a ordem das partes (multi-part WA/IG/TikTok)
      // eslint-disable-next-line no-await-in-loop
      await this.sendMessage(payload);
    }
    return;
  }
  this.gateConfirmedOnce = true;                     // one-shot anti-loop (store pode atrasar 1 tick)
  this.onSendReply();                                // assignee agora sou eu → envio automático
},
```

- **catch de `sendMessage` (:1548-1555)** — inserir ANTES do tratamento atual:

```js
if (error?.response?.status === 422 &&
    error.response.data?.error_code === 'assignment_required') {
  this.pendingGatePayloads.push(messagePayload);     // multi-part: N catches empilham na ordem
  this.$refs.assignToReplyDialog.show(error.response.data.meta);  // dono ATUALIZADO (corrida P16)
  return;
}
```

- **template**: ao lado do `<ReplyBoxBanner ...>` (:2274):

```html
<AssignToReplyDialog ref="assignToReplyDialog" @confirm="onAssignmentGateConfirmed" />
```

Caminhos que pulam `onSendReply` (áudio auto-send via `sendToConversation` :1409, templates WhatsApp,
shareLocation/shareContact): **sem dialog proativo, cobertos pelo 422 + catch acima** (o dialog abre
reativo). Registrado como UX aceita do v1.

### 3.3 i18n — `i18n/locale/{pt_BR,en}/conversation.json` (D-L2 é o dono na onda D)

```jsonc
"CONVERSATION": {
  "REPLY_GATE_DIALOG": {
    "TITLE": {
      "A": pt "Conversa sem responsável"               en "No one owns this conversation",
      "B": pt "Conversa de {name}"                     en "{name}'s conversation",
      "C": pt "Atendida pela IA {name}"                en "Handled by AI {name}",
      "D": pt "Você não faz parte deste time"          en "You're not part of this team"
    },
    "DESC": {
      "A": pt "Atribua a conversa a você para enviar a mensagem."
           en "Assign this conversation to yourself to send the message.",
      "B": pt "Essa conversa está sendo atendida por {name}. Assumir e enviar? {name} será notificado."
           en "This conversation is being handled by {name}. Take over and send? {name} will be notified.",
      "C": pt "Essa conversa está sendo atendida pela {name}. Ao assumir, a IA para de responder."
           en "This conversation is being handled by {name}. When you take over, the AI stops replying.",
      "D": pt "A conversa pertence ao time {team}. Escolha um dos seus times para assumir e enviar."
           en "This conversation belongs to team {team}. Pick one of your teams to take over and send."
    },
    "CONFIRM": {
      "A": pt "Atribuir a mim e enviar"                en "Assign to me and send",
      "B": pt "Assumir de {name} e enviar"             en "Take over from {name} and send",
      "C": pt "Assumir da {name} e enviar"             en "Take over from {name} and send",
      "D": pt "Atribuir e enviar"                      en "Assign and send"
    },
    "CANCEL":     pt "Cancelar"                         en "Cancel",
    "TEAM_LABEL": pt "Atribuir ao time"                 en "Assign to team",
    "NO_TEAMS":   pt "Você não participa de nenhum time — a conversa será atribuída a você mantendo o time atual."
                  en "You're not part of any team — the conversation will be assigned to you keeping the current team.",
    "AI_BADGE":   pt "Agente IA"                        en "AI Agent",
    "ERROR":      pt "Não foi possível atribuir a conversa, tente novamente"
                  en "Couldn't assign the conversation, please try again"
  },
  "REPLY_GATE_BANNER": {
    "UNASSIGNED": pt "Esta conversa não tem responsável — assuma para responder"
                  en "This conversation has no owner — take over to reply",
    "TAKEN":      pt "Atendida por {name} — assuma para responder"
                  en "Handled by {name} — take over to reply",
    "CTA":        pt "Assumir conversa"                 en "Take over"
  }
}
```

### 3.4 Specs (D-L2)

Vitest novo `AssignToReplyDialog.spec.js`: variante por estado (sem dono / colega / `type==='agent_bot'`
/ fora do time via myTeams); fail-open com store de teams vazio; `show(meta)` do 422 sobrescreve o store;
variante d lista SÓ `getMyTeams`; confirm despacha assignTeam→assignAgent na ordem (rethrow) e emite
`confirm`; 0 times degrada para self-assign. ReplyBox (aditivo no spec existente ou novo bloco):
`shouldShowAssignmentGate` (flag OFF false; private false; payload de nota forçada false; dona IA true);
fila `pendingGatePayloads` reenviada em ordem. Paridade i18n: NOVO
`i18n/specs/reply-gate-ptbr.spec.js` (molde `captain-ptbr.spec.js:26-35`, flattenKeys das subárvores
`CONVERSATION.REPLY_GATE_DIALOG` + `REPLY_GATE_BANNER` en↔pt_BR).

---

## 4. D3 — Banner proativo atualizado (Lote D-L2, mesmo arquivo)

### 4.1 `app/javascript/dashboard/components/widgets/conversation/ReplyBoxBanner.vue`

- setup: `const { isAssignmentGateEnabled } = useReplyAssignmentGate();`
- emits novo: `defineEmits(['openAssignDialog'])`.
- Texto do banner self-assign quando gate ON: usar `REPLY_GATE_BANNER.UNASSIGNED`/`TAKEN` (com nome do
  dono — inclusive IA via `assignee.type === 'agent_bot'`); CTA (`REPLY_GATE_BANNER.CTA`) **emite
  `openAssignDialog`** em vez de `onClickSelfAssign` (o dialog D2 vira o caminho único de assunção).
- Gate OFF: comportamento atual INTACTO (`onClickSelfAssign`/`TeamSelectionModal` preservados — eles
  continuam sendo o fluxo do Clássico).
- O fluxo **bot-handoff em PENDING (:49-53) não muda** (risco do dossiê: preservar).
- ReplyBox: `<ReplyBoxBanner ... @open-assign-dialog="$refs.assignToReplyDialog.show()" />`.

Spec (vitest aditivo): gate ON → CTA emite evento e não despacha assignAgent; gate OFF → fluxo atual;
banner suprimido em nota privada (já coberto por `isUserTyping`).

---

## 5. D4 — Notificar o assignee anterior (Lote D-L3)

### 5.1 `app/models/notification.rb`

- `NOTIFICATION_TYPES` (:38-47): append `conversation_unassignment: 10` (**9 é reservado** para
  `conversation_orphaned` da Fase C/C10.4; se C-B3 ainda não aplicou, deixar comentário
  `# 9: conversation_orphaned (Fase C)` e usar 10 mesmo assim — gap de enum é inofensivo, renumerar é
  PROIBIDO: NotificationSetting deriva os bits FlagShihTzu do valor, `notification_setting.rb:30-34`).
- `push_message_title` (map :132-141): entry
  `'conversation_unassignment' => 'notifications.notification_title.conversation_unassignment'` +
  branch de interpolação (o grupo existente só passa `display_id`; este leva o nome de quem assumiu):

```ruby
elsif notification_type == 'conversation_unassignment'
  I18n.t(i18n_key, display_id: conversation.display_id,
                   taker: conversation.assignee&.available_name || secondary_actor&.available_name || '')
```

- `push_message_body` (:157-171): somar `'conversation_unassignment'` ao branch de
  `'conversation_assignment'` (última incoming/outgoing).

### 5.2 `app/listeners/notification_listener.rb` (`assignee_changed`, :16-35)

```ruby
def assignee_changed(event)
  conversation, account = extract_conversation_and_account(event)
  assignee = conversation.assignee

  notify_previous_assignee(event, conversation, account)   # D4 — ANTES dos guards existentes

  return if assignee.blank?
  return if event.data[:notifiable_assignee_change].blank?
  return if conversation.pending?
  # ... NotificationBuilder conversation_assignment (existente, intacto)
end

private

# D4 (D-9): quem PERDEU a conversa é notificado. Caminho próprio, FORA do guard
# notifiable_assignee_change — que é false em self-assign, exatamente o roubo D-9.
# Gated pela flag (DD-7): Clássico fica como hoje.
def notify_previous_assignee(event, conversation, account)
  return unless account.reply_assignment_gate_enabled?
  return if conversation.pending?

  old_id, new_id = event.data[:changed_attributes]&.dig('assignee_id')   # previous_changes [old, new]
  return if old_id.blank? || new_id.blank? || old_id == new_id           # limbo é assunto do vigia C10
  return if old_id == Current.user&.id                                   # auto-desatribuição não notifica

  previous_assignee = account.users.find_by(id: old_id)                  # pode ter saído da conta
  return if previous_assignee.blank?

  NotificationBuilder.new(
    notification_type: 'conversation_unassignment',
    user: previous_assignee,
    account: account,
    primary_actor: conversation
    # secondary_actor default = Current.user (quem executou) — notification_builder.rb:36
  ).perform
end
```

Interação com `RemoveDuplicateNotificationJob` (notification.rb:208): dedupe é por
`(user_id, primary_actor_id)` — a notificação de `conversation_assignment` do NOVO dono e a de
`conversation_unassignment` do ANTIGO não se tocam (usuários distintos). Para o MESMO usuário, a
unassignment substitui a assignment antiga da mesma conversa (mantém a mais recente) — correto.

### 5.3 Email — `app/mailers/agent_notifications/conversation_notifications_mailer.rb` + template

Método novo (molde `conversation_assignment`, :14-24; `EmailNotificationService` chama
`public_send(type, primary_actor, user, secondary_actor)` — `email_notification_service.rb:23-27`):

```ruby
def conversation_unassignment(conversation, agent, user)
  return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
  return unless smtp_config_set_or_development?

  @agent = agent
  @conversation = conversation
  @taker = @conversation.assignee || user
  subject = I18n.t('notifications.notification_title.conversation_unassignment',
                   display_id: @conversation.display_id, taker: @taker&.available_name)
  @action_url = app_account_conversation_url(account_id: @conversation.account_id,
                                             id: @conversation.display_id)
  send_mail_with_liquid(to: @agent.email, subject: subject) and return
end
```

NOVO `app/views/mailers/agent_notifications/conversation_notifications_mailer/conversation_unassignment.liquid`
(copiar `conversation_assignment.liquid`, copy: "a conversa que estava com você foi assumida por
{{taker}}" + link). Subject via i18n (locale default pt_BR do app cobre; método antigo hardcoded EN é
legado — não tocar).

### 5.4 Defaults de subscrição — `app/models/account_user.rb:46-51`

```ruby
setting.selected_email_flags = [:email_conversation_assignment]
setting.selected_push_flags = [:push_conversation_assignment, :push_conversation_unassignment]
```

Usuários NOVOS nascem com push do takeover ligado; usuários EXISTENTES ficam **in-app only** até
ligarem na preferência (sem backfill — working tree only, sem data migration; registrado como
limitação consciente, o sino in-app sempre é criado: `notification_builder.rb:25-29`).

### 5.5 Frontend (chaves gravadas pelo D-L4 por contrato — ver DD-13)

- `generalSettings.json` `NOTIFICATIONS_PAGE.TYPE_LABEL` (en:209-218 + pt_BR):
  `"conversation_unassignment"`: pt `"Conversa assumida por colega"` / en `"Conversation taken over"`.
- `settings/profile/constants.js` (:1-37): entry
  `{ label: 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.CONVERSATION_UNASSIGNED', value: 'conversation_unassignment' }`
  após CONVERSATION_ASSIGNED.
- `settings.json` (en:196-198 + pt_BR): `"CONVERSATION_UNASSIGNED"`: pt
  `"Uma conversa sua foi assumida por outra pessoa"` / en
  `"A conversation assigned to you is taken over by someone else"`.

### 5.6 Specs (D-L3)

`spec/listeners/notification_listener_spec.rb` (aditivo): roubo via self-assign (A→B onde B=Current.user)
→ B NÃO recebe assignment (guard existente) e A RECEBE unassignment; admin reatribui A→B → A recebe
unassignment E B recebe assignment; old==new no-op; old nil (era órfã) no-op; new nil (desatribuição)
no-op; old==Current.user (auto-soltou) no-op; flag OFF no-op; pending no-op; old fora da conta no-op.
`spec/models/notification_spec.rb` (aditivo): título interpolado com taker (pt_BR e en), push body.
`spec/mailers/.../conversation_notifications_mailer_spec.rb` (aditivo): método novo renderiza e usa o
subject i18n. Spec de integração: takeover dispara `RemoveDuplicateNotificationJob` sem destruir a
notificação do outro usuário.

---

## 6. D5 — i18n consolidado da fase (distribuído nos lotes; resumo de paridade)

| Arquivo | Chaves novas | Dono (onda D) |
|---|---|---|
| `config/locales/{en,pt_BR}.yml` | `conversations.reply_assignment_gate.assignment_required`, `notifications.notification_title.conversation_unassignment` | **D-L1** |
| `i18n/locale/{pt_BR,en}/conversation.json` | `CONVERSATION.REPLY_GATE_DIALOG.*`, `CONVERSATION.REPLY_GATE_BANNER.*` | **D-L2** |
| `i18n/locale/{pt_BR,en}/generalSettings.json` | `GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.*`, `NOTIFICATIONS_PAGE.TYPE_LABEL.conversation_unassignment` | **D-L4** |
| `i18n/locale/{pt_BR,en}/settings.json` | `PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.CONVERSATION_UNASSIGNED` | **D-L4** |

Specs de paridade (molde `i18n/specs/captain-ptbr.spec.js` — flattenKeys por SUBÁRVORE, nunca full-file:
`generalSettings.json` já tem 3 chaves pt-only pré-existentes que quebrariam comparação total):
- `i18n/specs/reply-gate-ptbr.spec.js` (D-L2) — subárvores de conversation.json;
- `i18n/specs/attendance-mode-ptbr.spec.js` (D-L4) — subárvores de generalSettings.json + settings.json.
Backend: aditivo em spec existente ou NOVO `spec/lib/reply_gate_i18n_spec.rb` (D-L1) — asserts de
`I18n.t` das 2 chaves novas em `:en` e `:'pt-BR'` sem fallback-miss.

---

## 7. D6 — Fallback 422 no frontend (Lote D-L2, mesmos arquivos)

### 7.1 `app/javascript/dashboard/store/modules/conversations/actions.js`

- `createPendingMessageAndSend` (:405-408): **propagar o erro** —

```js
createPendingMessageAndSend: async ({ dispatch }, data) => {
  const pendingMessage = createPendingMessage(data);
  return dispatch('sendMessageWithData', pendingMessage);   // era fire-and-forget (unhandled rejection)
},
```

- `sendMessageWithData` catch (:428-439): **suprimir a bolha FAILED** no gate —

```js
} catch (error) {
  const errorMessage = error.response ? error.response.data.error : undefined;
  if (error.response?.data?.error_code === 'assignment_required') {
    commit(types.REMOVE_PENDING_MESSAGE, pendingMessage);   // sem bolha "falhou" + dialog (D6)
  } else {
    commit(types.ADD_MESSAGE, {
      ...pendingMessage, meta: { error: errorMessage }, status: MESSAGE_STATUS.FAILED,
    });
  }
  throw error;
}
```

Efeito colateral consciente (registrado): com o `return dispatch`, QUALQUER falha de envio agora chega
ao catch do ReplyBox e mostra o toast de erro além da bolha FAILED — melhoria (o catch :1548 já existia
mas era inalcançável neste caminho).

### 7.2 Mutation nova — `store/mutation-types.js` + `store/modules/conversations/index.js`

`mutation-types.js:46` já declara `DELETE_MESSAGE` **sem implementação** — para não colidir com a
semântica de delete persistido, criar tipo próprio: `REMOVE_PENDING_MESSAGE: 'REMOVE_PENDING_MESSAGE'`.
Em `conversations/index.js` (junto de `ADD_MESSAGE`, :290):

```js
[types.REMOVE_PENDING_MESSAGE](_state, message) {
  const chat = findConversation(_state, message.conversation_id);
  if (!chat) return;
  chat.messages = chat.messages.filter(m => m.id !== message.id);
},
```

### 7.3 ReplyBox

Já especificado em §3.2: catch empilha `messagePayload` + `show(meta)` com o dono atualizado do 422;
dialog idempotente dedupe os N 422 do multi-part (`sendMessageAsMultipleMessages`, :1432); confirmação
reenvia a fila **na ordem**. Corrida P16: o segundo agente vê o dialog reaberto com
`meta.current_assignee` novo (não depende do timing do websocket — DD-8/§3.1 `overrideMeta`).

### 7.4 Specs

`store/modules/specs/conversations/actions.spec.js` (aditivo): 422 com error_code → commit
`REMOVE_PENDING_MESSAGE` (sem ADD_MESSAGE FAILED) + rejeição propaga; erro comum → FAILED como hoje.
Mutation spec: remove só a pendente certa. Vitest do ReplyBox: catch empilha e reabre dialog com meta.

---

## 8. D7 — Toggle "Modo de atendimento" (Lote D-L4)

### 8.1 NOVO `app/javascript/dashboard/routes/dashboard/settings/account/components/AttendanceModeToggle.vue`

Molde `DashboardKpiStrip.vue` (SectionLayout + `useAccount().updateAccount` + `useAlert`) + Dialog de
confirmação components-next. Forma final (esqueleto):

```vue
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const confirmDialogRef = ref(null);
const pendingMode = ref(null);
const isUpdating = ref(false);

const currentMode = computed(() =>
  currentAccount.value?.settings?.reply_assignment_gate ? 'gated' : 'classic'
);
const MODES = ['classic', 'gated'];

const selectMode = mode => {
  if (mode === currentMode.value || isUpdating.value) return;
  pendingMode.value = mode;
  confirmDialogRef.value.open();
};

const confirmChange = async () => {
  isUpdating.value = true;
  try {
    await updateAccount({ reply_assignment_gate: pendingMode.value === 'gated' });
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.API.ERROR'));
  } finally {
    isUpdating.value = false;
    confirmDialogRef.value.close();
    pendingMode.value = null;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.NOTE')"
    with-border
  >
    <div class="grid gap-3 sm:grid-cols-2">
      <button
        v-for="mode in MODES" :key="mode" type="button"
        class="flex flex-col items-start gap-2 rounded-xl border p-4 text-left transition-colors"
        :class="currentMode === mode
          ? 'border-n-brand ring-1 ring-n-brand bg-n-brand/5'
          : 'border-n-weak hover:border-n-slate-7'"
        :aria-pressed="currentMode === mode"
        @click="selectMode(mode)"
      >
        <span class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <span :class="mode === 'classic' ? 'i-lucide-layout-list' : 'i-lucide-shield-check'" class="size-4" />
          {{ t(`GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.${mode.toUpperCase()}.TITLE`) }}
          <span v-if="currentMode === mode"
                class="rounded-md bg-n-brand/10 px-1.5 py-0.5 text-xs font-medium text-n-brand">
            {{ t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.ACTIVE') }}
          </span>
        </span>
        <span class="text-body-main text-n-slate-11">
          {{ t(`GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.${mode.toUpperCase()}.DESCRIPTION`) }}
        </span>
      </button>
    </div>

    <Dialog
      ref="confirmDialogRef"
      type="alert"
      :title="t(`GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.${(pendingMode || 'gated').toUpperCase()}.TITLE`)"
      :description="t(`GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.${(pendingMode || 'gated').toUpperCase()}.DESCRIPTION`)"
      :confirm-button-label="t('GENERAL_SETTINGS.FORM.ATTENDANCE_MODE.CONFIRM.ACTION')"
      :is-loading="isUpdating"
      @confirm="confirmChange"
    />
  </SectionLayout>
</template>
```

### 8.2 `app/javascript/dashboard/routes/dashboard/settings/account/Index.vue`

Import + montar `<AttendanceModeToggle />` logo após `<DashboardKpiStrip />` (:247). Rota já é
admin-only (`account.routes.js:10`); backend já é admin-only (`AccountPolicy#update?`) e o param já está
whitelisted (C-F0.2).

### 8.3 i18n — `generalSettings.json` (pt_BR + en), sob `GENERAL_SETTINGS.FORM`

```jsonc
"ATTENDANCE_MODE": {
  "TITLE":  pt "Modo de atendimento"  en "Attendance mode",
  "NOTE":   pt "Define como sua equipe responde conversas nesta conta."
            en "Defines how your team replies to conversations in this account.",
  "ACTIVE": pt "Ativo"                en "Active",
  "CLASSIC": {
    "TITLE": pt "Clássico"            en "Classic",
    "DESCRIPTION": pt "Como hoje: tabs Minhas/Não atribuídas/Todas, qualquer agente responde, opção \"Nenhum\" disponível."
                   en "As today: My/Unassigned/All tabs, any agent can reply, \"None\" option available."
  },
  "GATED": {
    "TITLE": pt "Atribuição obrigatória"  en "Required assignment",
    "DESCRIPTION": pt "Só o responsável responde. Quem não é dono assume com 1 clique no envio; tabs Minhas/IA/Todas; sem opção \"Nenhum\"; vigia re-triagem conversas órfãs."
                   en "Only the owner replies. Non-owners take over in 1 click on send; My/AI/All tabs; no \"None\" option; watchdog re-triages orphaned conversations."
  },
  "CONFIRM": {
    "ACTION": pt "Trocar modo"        en "Switch mode",
    "GATED": {
      "TITLE": pt "Ativar atribuição obrigatória?"  en "Enable required assignment?",
      "DESCRIPTION": pt "A partir de agora só o responsável responde cada conversa; as tabs mudam para Minhas/IA/Todas e a opção \"Nenhum\" some. Vale na hora, sem deploy."
                     en "From now on only the owner replies to each conversation; tabs become My/AI/All and the \"None\" option disappears. Takes effect immediately."
    },
    "CLASSIC": {
      "TITLE": pt "Voltar ao modo clássico?"        en "Back to classic mode?",
      "DESCRIPTION": pt "O gate de resposta, o dialog de assunção e as tabs novas são desligados. Tudo volta a funcionar como hoje, na hora."
                     en "The reply gate, the takeover dialog and the new tabs are turned off. Everything goes back to current behavior immediately."
    }
  },
  "API": {
    "SUCCESS": pt "Modo de atendimento atualizado"  en "Attendance mode updated",
    "ERROR":   pt "Não foi possível atualizar, tente novamente"  en "Couldn't update, please try again"
  }
}
```

(+ as chaves do D4 em TYPE_LABEL/settings.json/profile constants — §5.5, contrato DD-13.)

### 8.4 Specs

Vitest `AttendanceModeToggle.spec.js`: card ativo reflete `settings.reply_assignment_gate`
(true/false/ausente→classic); selecionar o modo já ativo é no-op; confirmar despacha
`updateAccount({ reply_assignment_gate })` correto; erro → alert de erro e modo não muda visualmente.
Paridade: `attendance-mode-ptbr.spec.js` (§6).

---

## 9. D8 — Stack de efeitos visuais (Lotes D-L5 instalação / D-L6 componentes / D-L7 aplicação)

### 9.1 D-L5 — Instalação (package.json + tailwind + globals)

1. **Instalar** (pnpm 10.2.0; conferir warnings de build scripts — nenhuma das 5 tem postinstall
   essencial conhecido):
   ```bash
   pnpm add motion-v@2.3.0 @number-flow/vue@0.5.0 @formkit/auto-animate@0.9.0 canvas-confetti@1.9.4 tailwindcss-animated@2.1.0
   ```
2. **`tailwind.config.js`**:
   - plugins (:332-348): somar `require('tailwindcss-animated')` ao array (após typography).
   - `theme.keyframes` top-level (:245+, junto de `shake`/`shimmer` — NUNCA em extend):
     ```js
     'head-shake': {
       '0%, 100%': { transform: 'translateX(0)' },
       '12.5%': { transform: 'translateX(-6px) rotateY(-9deg)' },
       '37.5%': { transform: 'translateX(5px) rotateY(7deg)' },
       '62.5%': { transform: 'translateX(-3px) rotateY(-5deg)' },
       '87.5%': { transform: 'translateX(2px) rotateY(3deg)' },
     },
     'glow-pulse': {
       '0%, 100%': { boxShadow: '0 0 0 0 rgb(var(--ruby-9) / 0.35)' },
       '50%': { boxShadow: '0 0 8px 2px rgb(var(--ruby-9) / 0.15)' },
     },
     ```
     e `theme.animation` (:313+): `'head-shake': 'head-shake 0.8s ease-in-out 1'`,
     `'glow-pulse': 'glow-pulse 2s ease-in-out infinite'`. (Nome do token ruby: conferir o nome REAL
     da CSS var no theme do fork na implementação — regra: token, nunca hex.)
   - **DOCUMENTAR no próprio config** (comentário): `shake` e `wiggle` do fork mascaram as classes
     homônimas do tailwindcss-animated (top-level do user vence) — para efeitos novos usar
     `animate-jump-in`/`animate-fade-up` (sem colisão) ou os keyframes custom acima.
3. **`app/javascript/dashboard/App.vue`** (template :174-204): envolver o conteúdo do `div#app` com
   `<MotionConfig reduced-motion="user">` (componente renderless do motion-v; Options API convive — é
   componente, não plugin). Atenção ao `v-if` do loading state: o wrapper entra DENTRO do `div#app`,
   abraçando banners + router-view + boxes.
4. **`app/javascript/entrypoints/dashboard.js`** (:47, `createApp`): registrar
   `app.use(autoAnimatePlugin)` (`@formkit/auto-animate/vue`) — habilita a diretiva `v-auto-animate`
   global (3,2KB, zero deps).
5. **Validação de bundle**: `pnpm build` e conferir o tamanho do chunk do motion-v (risco do dossiê:
   framer-motion/motion-dom como deps — orçamento ~7,5KB sync via LazyMotion + lazy features conforme
   doc motion-v; se o chunk sync passar de ~30KB, adotar `LazyMotion` com features assíncronas antes do
   aceite). `@number-flow/vue` registra custom element `<number-flow>` — se o vite/vue reclamar,
   configurar `compilerOptions.isCustomElement` (risco baixo, validar no primeiro uso).

### 9.2 D-L6 — Componentes portados (NOVA pasta `app/javascript/dashboard/components-next/effects/`)

Padrão da pasta: `<script setup>` com defineProps runtime (sem TS), tokens via `rgb(var(--token))`,
`<style scoped>` com `@keyframes` próprios (precedente estabelecido: `animated-icons/BotIcon.vue:60-64`),
`@media (prefers-reduced-motion: reduce)` zerando animação em TODOS.

- **`BorderBeam.vue`** (Inspira UI doc v1, CSS puro, 0 deps): feixe percorrendo a borda via
  `@property --angle` + conic-gradient; props `duration` (s), `size`, `colorFrom`/`colorTo` com default
  em tokens (ex. `rgb(var(--blue-9))`/`rgb(var(--iris-9))`); fallback sem `@property` (Baseline 2024) =
  borda estática colorida; reduced-motion = sem animação (borda estática).
- **`GlowBorder.vue`**: glow pulsante de box-shadow com token configurável (uso: tab de alerta, badge).
- **`AnimatedCheckmark.vue`**: SVG `stroke-dashoffset` animado, `currentColor` (dark mode grátis),
  molde animated-icons; prop `size`.
- **`useConfetti.js`** (helper, mesmo diretório):
  ```js
  let firedThisSession = false;
  export async function fireTakeoverConfetti() {
    if (firedThisSession) return;                       // celebração só na 1ª assunção da sessão
    firedThisSession = true;
    const { default: confetti } = await import('canvas-confetti');   // lazy — fora do bundle inicial
    confetti({ particleCount: 30, scalar: 0.8, spread: 60, origin: { y: 0.8 },
               disableForReducedMotion: true });
  }
  ```
- Specs vitest: render dos 3 componentes (props default, classe de reduced-motion presente), helper
  dispara import 1x.

### 9.3 D-L7 — Aplicação nas superfícies (APÓS C-F3 e D-L5)

- **`components/ui/Tabs/TabsItem.vue:87-94`** (badge global de TODAS as tabs — `woot-tabs-item` via
  WootUiKit): trocar `<span>{{ getItemCount }}</span>` por NumberFlow **opt-in**:
  ```html
  <NumberFlow v-if="animatedCount" :value="getItemCount" />
  <span v-else>{{ getItemCount }}</span>
  ```
  prop nova `animatedCount: { type: Boolean, default: false }` — zero mudança nas outras tabs do app;
  respeitar `useReducedMotion` já importado no arquivo (`:3`) — com reduced motion, manter o span.
- **`components/widgets/ChatTypeTabs.vue`**: repassar `:animated-count="true"` aos
  `woot-tabs-item`; tab condicional "Não atribuídas" (variant alert da C4.6/DC-6) ganha
  `animate-jump-in` na entrada + `animate-head-shake` 1x quando `unAssignedCount` INCREMENTA (watcher) +
  `GlowBorder`/`animate-glow-pulse` no badge — tokens ruby, light+dark.
- **`components/ChatList.vue`**: `v-auto-animate` no container da lista de conversas (entrada/saída/
  reorder FLIP automático ao trocar de tab/assumir conversa). Guard: aplicar a diretiva apenas quando
  `!useReducedMotion()` (auto-animate respeita a flag via options `duration: 0`).
- Aplicações **opcionais pós-QA** (stretch, não bloqueiam aceite): `BorderBeam` no badge "Agente IA" da
  página de usuários (arquivo da C-F2 `AIAgentsSection.vue`) e dot `animate-ping` duplo na tab IA.

---

## 10. Fase E (Lote E-L8)

### 10.1 E1 — Regra #53 / equivalentes (runbook, SEM mudança de código agora)

NOVO `plano/runbook-e2e-validacao.md` (não editar `ia-consolidado.md` em paralelo — referenciar):
- **Fato verificado**: regra **#53 NÃO existe em homolog** (vive só na Tozi PROD; account 6 homolog tem
  zero regras). A equivalente funcional na sandbox é a **#29 "opa" da account 1** (SimplexIA):
  `conversation_opened`, inbox 16, `assign_agent → ['nil']`, **ATIVA** — zera o assignee humano a cada
  reopen e **quebra o teste E2E §5.3 #11**.
- **Procedimento (na janela de validação E2E, NÃO agora)**: `AutomationRule.find(29).update!(active: false)`
  via rails runner ANTES do roteiro §5.3; reativar (ou substituir pela regra de triagem definitiva) ao
  final; registrar no log da validação.
- Nota técnica (do dossiê): `assign_agent('nil')` só zera `assignee_id` (`action_service.rb:43-44`) e
  NÃO limpa o espelho (`reset_agent_bot_when_assignee_present` exige assignee presente) — uma #53-like
  não cala a IA no modelo novo; o dano é desatribuir HUMANOS no reopen e brigar com a triagem.
- **Checklist da virada (§6 item 3)**: verificação READONLY da #53 em PROD antes de ligar a triagem
  (impossível validar de homolog); a substituta E1 re-triagem apenas órfãs REAIS (a regra nova de
  triagem `conversation_created` + vigia C10 cobrem; nenhuma regra `conversation_opened → assign_agent
  nil` sobrevive à virada).
- Account 3 tem 6 regras com `assign_agent nil` (ids 3,5,6,7,11,12) — relevantes SÓ se o gate for
  ligado lá; registrar.

### 10.2 E2 — Padronização dos call-sites de atribuição

1. **`scripts/spx/tozi/consolida_conversas_duplicadas.rb:60-62`** (ÚNICO que quebra a invariante:
   `update_columns` com `assignee_id` pula `reset_agent_bot_when_assignee_present` — re-execução
   pós-virada poderia persistir `assignee_id` E `assignee_agent_bot_id` juntos):
   ```ruby
   upd = { additional_attributes: attrs, status: Conversation.statuses[:open],
           last_activity_at: ... }
   # assignee SAI do update_columns — atribuição SEMPRE pelo trilho canônico (invariante Fase A):
   upd[:campaign_id] = camp if camp && survivor.campaign_id.nil?
   survivor.update_columns(upd)
   Conversations::AssignmentService.new(conversation: survivor, assignee_id: corretor).perform if corretor
   ```
   (assinatura real verificada: `initialize(conversation:, assignee_id:, assignee_type: nil)` —
   `assignment_service.rb:2`; `assign_agent` já zera o espelho explicitamente.)
2. **`app/jobs/spx/tozi/disparo_lead_job.rb:127`**:
   ```ruby
   if conversation.assignee_id != assignee_id
     Conversations::AssignmentService.new(conversation: conversation, assignee_id: assignee_id).perform
   end
   ```
   (o `create!` da :139 fica — conversa nova nasce sem espelho; callbacks rodam.)
3. **`app/jobs/agents/destroy_job.rb:41`** — SÓ comentário (decisão do brief):
   ```ruby
   # NOTA (Fase E/D-12): bulk update_all não dispara CONVERSATION_UPDATED — as conversas
   # viram órfãs silenciosas. Mitigação estrutural: vigia de órfãs (C10) re-triagem + notifica.
   ```
4. Specs: `spec/jobs/spx/tozi/disparo_lead_job_spec.rb` (aditivo ou novo): reatribuir conversa cujo dono
   é espelho captain → espelho limpo no MESMO save (invariante preservada). O script de consolidação não
   tem harness de spec — validação manual documentada no runbook (teste §5.3 #14).

### 10.3 E4 — Telemetria AssistantLog (auditoria da virada)

1. **`enterprise/app/models/captain/assistant_log.rb:7-12`** — ampliar a whitelist:
   ```ruby
   EVENT_TYPES = %w[
     response debounce_skip debounce_fire router_skip business_hours_skip
     handoff media_process humanizer_split dedup_skip error copilot_trigger
     mirror_assigned mirror_released human_takeover
   ].freeze
   ```
2. **`enterprise/app/models/enterprise/concerns/conversation.rb`** (included block, :4-21) — watcher
   novo (DD-11; `captain_assistant_id` é NOT NULL → capturar o assistant pelo VALOR ANTIGO do
   saved_change, NUNCA depois de zerado; `after_commit` para não logar transação que sofre rollback):
   ```ruby
   attr_accessor :captain_release_reason
   after_commit :log_captain_mirror_transition, if: -> { saved_change_to_assignee_agent_bot_id? }
   ```
   ```ruby
   # E4: trilha de auditoria da virada — quem (IA) assumiu/soltou cada conversa e por quê.
   def log_captain_mirror_transition
     old_id, new_id = saved_change_to_assignee_agent_bot_id
     log_mirror_event(new_id, 'mirror_assigned', { previous_agent_bot_id: old_id }) if new_id.present?
     return unless old_id.present? && new_id.blank?

     event, reason = captain_release_event_and_reason
     log_mirror_event(old_id, event, { reason: reason, new_assignee_id: assignee_id })
   end

   def captain_release_event_and_reason
     return %w[mirror_released resolve] if saved_change_to_status? && resolved?     # A2e
     return %w[human_takeover assignment] if assignee_id.present?                   # reset core / dialog D2
     return %w[human_takeover reply] if captain_release_reason == 'human_reply'     # A2c
     %w[mirror_released unassigned]                                                 # automação/None
   end

   def log_mirror_event(agent_bot_id, event_type, payload)
     assistant = AgentBot.find_by(id: agent_bot_id)&.captain_assistant
     return if assistant.blank?

     Captain::AssistantLog.create!(captain_assistant: assistant, conversation: self,
                                   event_type: event_type, payload: payload)
   rescue StandardError => e
     Rails.logger.warn("[Captain] assistant_log de atribuição falhou: #{e.message}")
   end
   ```
   (`mirror_assigned` cobre nil→espelho, humano→espelho e IA→IA — payload leva o espelho anterior;
   nenhuma referência a Captain entra no core `conversation.rb:318-322`.)
3. **`enterprise/app/models/enterprise/message.rb:38-47`** (A2c) — 1 linha antes do update:
   ```ruby
   conversation.captain_release_reason = 'human_reply'
   conversation.update!(assignee_agent_bot_id: nil)
   ```
4. **Frontend — as 2 listas hardcoded**:
   - `routes/dashboard/captain/assistants/logs/Index.vue:6-33`: somar
     `{ value: 'mirror_assigned', label: 'Mirror Assigned' }`, `{ value: 'mirror_released', label:
     'Mirror Released' }`, `{ value: 'human_takeover', label: 'Human Takeover' }` + cores
     (`mirror_assigned: 'bg-blue-100 text-blue-800'`, `mirror_released: 'bg-slate-100 text-slate-800'`,
     `human_takeover: 'bg-amber-100 text-amber-800'`).
   - `components-next/agents/tabs/LogsTab.vue:22-39`: **corrigir o drift de carona** — substituir
     `'debounce', 'copilot', 'inbox'` (não existem no backend) pela lista real do modelo + os 3 novos;
     atualizar `eventTypeConfig` com ícones/cores equivalentes.
   - Débito registrado (não resolvido aqui): labels dessas telas são EN hardcoded pré-existentes —
     i18n-ização completa fica para um passe próprio (violaria o escopo "de carona").
5. Specs: NOVO `spec/enterprise/models/captain_mirror_logging_spec.rb` — atribuição do espelho loga
   `mirror_assigned` (payload com anterior em IA→IA); resolve loga `mirror_released/resolve`; atribuição
   humana (reset core) loga `human_takeover/assignment`; A2c loga `human_takeover/reply`; automação
   `assign_agent nil`… espelho intacto (não loga); espelho sem assistant (órfão) não explode; rollback
   da transação não loga (after_commit).

### 10.4 E3 — Mapa de specs faltantes (consolidação; quem entrega cada um)

| Spec faltante (dossiê) | Entregue por |
|---|---|
| Guard 422 `assignment_required` — variantes + bypasses + flag off | D-L1 (§2.4) |
| Self-assign na criação de conversa | D-L1 (§2.4) |
| `authorize_team_access` 403 (implementado na Fase 0/A SEM spec) | D-L1 (carona, §2.4) |
| Notificação ao assignee anterior (listener/notification/mailer) | D-L3 (§5.6) |
| Paridade i18n das strings novas (en↔pt_BR, por subárvore) | D-L1/D-L2/D-L4 (§6) |
| 422 → REMOVE_PENDING_MESSAGE + reenvio em ordem | D-L2 (§7.4) |
| Toggle D7 (modo reflete settings, updateAccount) | D-L4 (§8.4) |
| Eventos novos do AssistantLog + invariantes do watcher | E-L8 (§10.3) |
| DisparoLeadJob via AssignmentService preserva exclusividade | E-L8 (§10.2) |
| Espelho fora de RELATÓRIOS (gap residual do C8 — assignable_agents e round-robin já travados) | E-L8: NOVO `spec/enterprise/models/agent_bot_reports_exclusion_spec.rb` — conversa de espelho não conta em métricas por agente (V2 reports agent metric) |
| §5.1-B e §5.1-C inteiros | Fases B/C (fora deste design) |

### 10.5 E5 — Nota no vault (encerramento, ÚLTIMO passo do lote)

NOVO `vault/01-Permanentes/Padrao - IA como atendente via AgentBot-espelho.md` — escrever SÓ após o
aceite das fases (qualidade > volume): trilho espelho (D-1), gate por atribuição, exclusividade
humano×bot no mesmo save, gate universal D-4 (controller-level + bypasses source_id/private/bot-token),
flag em settings jsonb (bigint cheio — lição), notificação fora do guard notifiable (self-assign),
colisão keyframes tailwindcss-animated, lições novas descobertas na implementação. Linkar dos MOCs
(`MOC - Engineering`).

---

## 11. LOTES de implementação (arquivos ESTRITAMENTE disjuntos dentro das Fases D+E)

```
   pré-requisito EXTERNO: C-F0 aplicada (helper/composable/whitelist da flag)
            │
   ┌────────┴───────────────────────────────────────────────────────────────┐
   ▼            ▼            ▼            ▼            ▼            ▼
 D-L1         D-L3         D-L4         D-L5         D-L6         E-L8        ← ONDA D-1 (paralelos)
(guard)    (notificação) (toggle-ui) (efeitos-inst)(efeitos-comp)(fase-e)
              [após C-B3]
   └──────────────┬─────────────────────────────────────────────────────────┘
                  ▼                          ▼
                D-L2                       D-L7                               ← ONDA D-2
         (dialog-replybox)           (efeitos-aplicação)
        [após C-F1 + C-B1;          [após C-F3 + D-L5]
         runtime: D-L5/D-L6]
```

| Lote | Tarefas | Arquivos (exclusivos do lote nas Fases D+E) |
|---|---|---|
| **D-L1 lote-guard-backend** | D1 + DD-2 + chaves backend (D5) + carona E3 | `app/controllers/api/v1/accounts/conversations/messages_controller.rb` · `app/controllers/api/v1/accounts/conversations_controller.rb` · `config/locales/en.yml` · `config/locales/pt_BR.yml` · NOVO `spec/lib/reply_gate_i18n_spec.rb` · `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` · `spec/controllers/api/v1/accounts/conversations_controller_spec.rb` |
| **D-L2 lote-dialog-replybox** | D2 + D3 + D6 | NOVO `components-next/Conversation/AssignToReplyDialog.vue` (+spec) · `components/widgets/conversation/ReplyBox.vue` · `components/widgets/conversation/ReplyBoxBanner.vue` · `store/modules/conversations/actions.js` · `store/modules/conversations/index.js` · `store/mutation-types.js` · `i18n/locale/{pt_BR,en}/conversation.json` · NOVO `i18n/specs/reply-gate-ptbr.spec.js` · `store/modules/specs/conversations/actions.spec.js` |
| **D-L3 lote-notificacao** | D4 backend | `app/models/notification.rb` · `app/listeners/notification_listener.rb` · `app/models/account_user.rb` · `app/mailers/agent_notifications/conversation_notifications_mailer.rb` · NOVO `app/views/mailers/.../conversation_unassignment.liquid` · `spec/listeners/notification_listener_spec.rb` · `spec/models/notification_spec.rb` · `spec/mailers/...` |
| **D-L4 lote-toggle-ui** | D7 + i18n frontend do D4 (contrato DD-13) | NOVO `routes/dashboard/settings/account/components/AttendanceModeToggle.vue` (+spec) · `routes/dashboard/settings/account/Index.vue` · `i18n/locale/{pt_BR,en}/generalSettings.json` · `i18n/locale/{pt_BR,en}/settings.json` · `routes/dashboard/settings/profile/constants.js` · NOVO `i18n/specs/attendance-mode-ptbr.spec.js` |
| **D-L5 lote-efeitos-instalacao** | D8a | `package.json` · `pnpm-lock.yaml` · `tailwind.config.js` · `app/javascript/entrypoints/dashboard.js` · `app/javascript/dashboard/App.vue` |
| **D-L6 lote-efeitos-componentes** | D8b | NOVOS `components-next/effects/BorderBeam.vue` · `GlowBorder.vue` · `AnimatedCheckmark.vue` · `useConfetti.js` (+specs) |
| **D-L7 lote-efeitos-aplicacao** | D8c | `components/ui/Tabs/TabsItem.vue` · `components/widgets/ChatTypeTabs.vue` · `components/ChatList.vue` (+vitest aditivos) |
| **E-L8 lote-fase-e** | E1 + E2 + E4 (+E5 no encerramento) | `scripts/spx/tozi/consolida_conversas_duplicadas.rb` · `app/jobs/spx/tozi/disparo_lead_job.rb` · `app/jobs/agents/destroy_job.rb` (comentário) · `enterprise/app/models/captain/assistant_log.rb` · `enterprise/app/models/enterprise/concerns/conversation.rb` · `enterprise/app/models/enterprise/message.rb` · `routes/dashboard/captain/assistants/logs/Index.vue` · `components-next/agents/tabs/LogsTab.vue` · NOVO `plano/runbook-e2e-validacao.md` · NOVO `spec/enterprise/models/captain_mirror_logging_spec.rb` · NOVO `spec/enterprise/models/agent_bot_reports_exclusion_spec.rb` · `spec/jobs/spx/tozi/disparo_lead_job_spec.rb` · NOVO `vault/01-Permanentes/Padrao - IA como atendente via AgentBot-espelho.md` (só no final) |

**Disjunção verificada item a item** dentro das Fases D+E: nenhum arquivo aparece em dois lotes →
paralelismo total dentro de cada onda, sem worktree isolation.

**Dependências (de ARQUIVO, entre fases/ondas — DD-13):**
- **C-F0 → D-L1, D-L3, D-L4** (helper `reply_assignment_gate_enabled?` / whitelist; e `en.yml`/`pt_BR.yml`
  têm a C-F0 como dona na onda C — D-L1 edita os MESMOS yml, então onda D-1 só começa com C-F0 aplicada).
- **C-B3 → D-L3** (mesmo `notification.rb`; se C-B3 atrasar, D-L3 usa o valor 10 deixando o 9 reservado
  e o lote que chegar depois resolve o merge trivial).
- **C-F1 → D-L2** (`conversation.json` + `actions.js` compartilhados) e **C-B1 → D-L2** (serializer
  `type: 'agent_bot'` é pré-requisito da variante c).
- **C-F3 → D-L7** (`ChatList.vue`/`ChatTypeTabs.vue`).
- **Runtime (não bloqueia edição, bloqueia validação): D-L5 → D-L2/D-L7** (motion-v/NumberFlow/
  auto-animate instalados para vitest/build) e **D-L6 → D-L2** (useConfetti/AnimatedCheckmark).
- **E-L8 independe de C e de D** (arquivos próprios) — pode rodar na onda D-1; só os testes E2E do
  runbook esperam tudo pronto.
- **Coordenação Paulo:** nenhum lote toca `enterprise/app/models/captain/assistant.rb` nem tools captain
  existentes. E-L8 toca `enterprise/message.rb` e `enterprise/concerns/conversation.rb` (Fase A
  commitada, fora da área ativa dele) — mesmo assim, avisar antes de aplicar o E-L8 e aplicar em
  edições aditivas pequenas.

**Riscos de execução por lote:**

| Risco | Lote | Mitigação |
|---|---|---|
| Guard matar echo WAHA (mensagens do celular sumirem) | D-L1 | bypass `source_id` + spec dedicada + teste manual com o app externo no QA |
| `render_assignment_required` quebrar o alert legado | D-L1 | manter chave `error` no payload + spec do shape |
| Dialog em loop (store não atualizou assignee) | D-L2 | one-shot `gateConfirmedOnce` + fail-open de teams |
| Bolha FAILED visível junto do dialog | D-L2 | `REMOVE_PENDING_MESSAGE` no error_code (DD-8) + spec |
| N dialogs no multi-part | D-L2 | `show()` idempotente + fila ordenada de payloads |
| Renumeração acidental do enum de notificação | D-L3 | valor fixo 10 + comentário "NUNCA renumerar" + spec congelando o valor |
| Tipo novo mudo (push/email off) p/ usuários antigos | D-L3 | in-app sempre criada; default ON só p/ novos (§5.4, documentado) |
| Toggle visível mas PATCH 403 (C-F0 ausente) | D-L4 | dependência dura C-F0; spec de request cobre no C |
| Colisão shake/wiggle do plugin | D-L5 | DD-10: só classes sem colisão + comentário no config |
| Chunk do motion-v estourar orçamento | D-L5 | medir no `pnpm build`; LazyMotion/async features antes do aceite |
| NumberFlow mudar TODAS as tabs do app | D-L7 | prop opt-in `animatedCount` (default false) |
| Watcher E4 logar em transação revertida / espelho órfão | E-L8 | `after_commit` + rescue + spec |
| Consolidação re-executada quebrar invariante | E-L8 | AssignmentService no script (pré-requisito do §5.3 #14) |
| Regra #29 ativa quebrar E2E #11 | E-L8 | runbook: desativar na janela de validação (NÃO agora) |

---

## 12. Validação da fase

### 12.1 Specs Rails (§5.1-D consolidado)

guard `assignment_required` (todas as variantes + bypasses + flag off + share_*) · self-assign na
criação · interação A2c×D1 (echo solta espelho; 422 não) · notificação ao anterior (todas as bordas +
flag off) · título/push/email do tipo novo · paridade i18n (subárvores) · eventos E4 (4 transições +
rollback) · DisparoLeadJob/invariante · espelho fora de relatórios · `authorize_team_access`.

```bash
bundle exec rspec spec/controllers/api/v1/accounts/conversations \
  spec/controllers/api/v1/accounts/conversations_controller_spec.rb \
  spec/listeners/notification_listener_spec.rb spec/models/notification_spec.rb \
  spec/mailers spec/lib/reply_gate_i18n_spec.rb spec/jobs/spx spec/enterprise
npx vitest run   # specs vitest dos lotes D-L2/D-L4/D-L6/D-L7 + i18n/specs
pnpm build       # orçamento de bundle do D8
```

### 12.2 Playwright (P7-P13 — light + dark, user de teste DEDICADO, evidências em `plano/evidencias/fase-d/`)

Pré-condição: flag ligável pela PRÓPRIA UI (D7) — sem console. Conta sandbox com: 1 assistant elegível,
2 agentes (A do time T1, B do time T2), 1 admin, conversas semeadas por variante.

| # | Cenário | Passos | Aceite |
|---|---|---|---|
| **P7** | Variante (a) | flag ON; agente A abre conversa SEM dono do time T1; digita; envia | dialog "Atribuir a mim e enviar" (slide-up/spring); confirmar → assignee = A no sidebar, mensagem na thread, draft nunca some; confete sutil na 1ª da sessão (e AUSENTE com reduced-motion emulado) |
| **P8** | Variante (b) | conversa do agente B (mesmo time de A); A digita e envia | dialog "Assumir de {B} e enviar" → assume e envia; sessão de B recebe sino `conversation_unassignment` ("assumida por A") |
| **P9** | Variante (c) | conversa atribuída ao espelho IA; A digita e envia | dialog "Assumir da {IA} e enviar" com badge IA → espelho limpo (IA some do sidebar), mensagem sai, conversa SAI da tab "IA" |
| **P10** | Variante (d) | admin (fora do time T1) em conversa do time T1; digita e envia | dialog com select dos times DO admin → escolhe → "Atribuir e enviar" → team + self atribuídos, mensagem sai |
| **P11** | Nota privada | conversa não-atribuída; modo nota; envia | SEM dialog, nota criada (e canal sem can_reply: nota forçada também sem dialog) |
| **P12** | DOM walker | varrer telas tocadas (dialog, banner, toggle, notificações, tabs) | sem i18n key vazada, ícones width/height>0, sem console errors, contraste ok nos 2 temas |
| **P13** | Toggle D7 | admin abre Configurações→Conta; troca Clássico→Obrigatório (confirma no dialog) e volta | reflete NA HORA sem deploy: tabs (Minhas/IA/Todas ↔ clássicas), None some/volta, dialog liga/desliga, banner muda; conta SEM assistant em modo obrigatório → sem tab IA, gate e tab condicional funcionam; agente comum não vê a página (rota admin) |
| **P16-bis** | Corrida (D6) | A e B abrem a mesma conversa órfã; A assume via dialog; B (que já digitou) envia | B recebe 422 → dialog REABRE com "Assumir de {A}" (meta do 422, sem bolha de falha); confirmar → mensagem de B sai |

### 12.3 Aceite das fases (espelha §4 do consolidado)

**D:** com a flag ligada — não-dono clica enviar → dialog certo por variante, mensagem sai após
confirmar e **nunca se perde**; nota privada passa; API direta sem atribuição → 422 estruturado;
corrida → segundo vê dialog atualizado; anterior é notificado no roubo; toggle liga/desliga tudo na
hora; **flag OFF → comportamento atual intacto** (specs + P13). Efeitos: dialog spring, contador
odômetro, tab de alerta animada, confete 1x — todos mudos sob `prefers-reduced-motion`.
**E:** scripts padronizados (invariante preservada sob re-execução); AssistantLog audita
assumiu/soltou com motivo; runbook E2E pronto (regra #29 mapeada); specs do mapa §10.4 verdes; nota no
vault escrita no encerramento.

---

## 13. openQuestions (contradições/tangências com D-1..D-13 — sancionar antes de codar o ponto)

- **OQ-D1 (D-4):** primeira mensagem na criação de conversa pelo dashboard (`conversations_controller#create`)
  — proposta = **self-assign automático do criador** com gate ON (DD-2). Alternativa = bypass puro
  (criador envia sem virar dono — furo na letra de D-4) ou 422 (quebra o modal de nova conversa, que
  não tem o dialog). Sancionar o self-assign.
- **OQ-D2 (D-9 × D-13):** a notificação ao assignee anterior foi **condicionada à flag**
  `reply_assignment_gate` (DD-7) para honrar "Clássico = tudo como hoje" (D-13). Com flag OFF, roubo de
  conversa NÃO notifica o anterior — se D-9 deve valer também no Clássico, remover o gate do listener
  (1 linha). Sancionar.
- **OQ-D3 (D-4):** respostas enviadas **pelo celular** (echoes do app WAHA externo, bypass por
  `source_id`; e echoes nativos via webhook) **não passam pelo gate** — "só o assignee responde" não é
  imposto fora do painel — e continuam soltando o espelho via A2c (atendente respondeu do celular → IA
  cala). Tecnicamente inevitável sem quebrar os echoes; comportamento especificado em spec (§2.4).
  Sancionar.
- **OQ-D4 (D-4):** variante (a) em conversa **sem time**: o dialog exige escolher um dos times DO
  usuário quando ele tem 2+ times (DD-5, precedente do banner atual + `team_required_for_resolution`) —
  refina a promessa "Atribuir a mim e enviar em 1 clique" da letra de D-4/D2 nesse caso de borda.
  Sancionar (alternativa: self-assign sem time e resolver o time só na resolução).
