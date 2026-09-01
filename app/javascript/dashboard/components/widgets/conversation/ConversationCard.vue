<script setup>
import { computed, inject, nextTick, reactive, ref, watch } from 'vue';
import { routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import { aiAccentVars } from 'dashboard/helper/aiAccent';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import ConversationContextMenu from './contextMenu/Index.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, default: null },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
  // Estes cinco so existem para montar o link da conversa (ver `conversationLink`):
  // a rota muda conforme a lista de onde o cartao veio (caixa, rotulo, time, pasta,
  // mencoes...). Quem renderiza a lista e o ConversationItem, que ja os repassa.
  activeLabel: { type: String, default: '' },
  teamId: { type: [String, Number], default: 0 },
  foldersId: { type: [String, Number], default: 0 },
  conversationType: { type: String, default: '' },
  conversationStatus: { type: String, default: '' },
  enableContextMenu: { type: Boolean, default: false },
  // Lista branca de itens do menu. Vazia = todos. A aba "Conversas anteriores" do
  // contato passa apenas ['open-new-tab', 'copy-link'].
  allowedContextMenuOptions: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'contextMenuToggle',
  'updateConversationStatus',
  'assignAgent',
  'assignTeam',
  'assignLabel',
  'removeLabel',
  'markAsUnread',
  'markAsRead',
  'assignPriority',
  'deleteConversation',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);
// O menu vive no cartao (nao na lista) porque cada cartao abre o SEU, com a posicao
// do ponteiro; o ContextMenu de ui/ so teleporta o conteudo para o body.
const showContextMenu = ref(false);
const contextMenu = reactive({ x: 0, y: 0 });
const dropdownButtonRef = ref(null);

const store = useStore();
// `inject(routerKey, null)` e nao `useRouter()`: os specs montam o cartao sem o
// plugin de rotas e o `useRouter()` injeta SEM default, entao cada monte imprimia
// um "injection not found" no stderr. Com o default explicito o cartao continua
// montavel fora do roteador, e o clique so nao navega.
const router = inject(routerKey, null);
const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');
const getContactById = useMapGetter('contacts/getContact');
const selectedChat = useMapGetter('getSelectedChat');
const getInboxById = useMapGetter('inboxes/getInbox');
const inboxesList = useMapGetter('inboxes/getInboxes');
const selectedInbox = useMapGetter('getSelectedInbox');
const { t } = useI18n();
const { isMessageRestricted } = useAgentIsolation();

const unreadCount = computed(() => props.chat.unread_count || 0);
const hasUnread = computed(() => unreadCount.value > 0);
const chatMetadata = computed(() => props.chat.meta || {});

// Quem renderiza o card passa so `:chat` (ConversationItem e ContactConversations).
// A prop `currentContact` existe como override — sem ela, o contato sai da propria
// conversa e cai num objeto vazio nomeado, nunca em undefined: o template le
// `.name` direto, e um undefined aqui derruba a lista inteira no render.
const resolvedContact = computed(() => {
  if (props.currentContact) return props.currentContact;

  const raw =
    props.chat.contact ||
    chatMetadata.value.contact ||
    chatMetadata.value.sender ||
    props.chat.sender ||
    props.chat.meta?.sender;

  if (!raw)
    return {
      id: null,
      name: 'Unknown',
      thumbnail: '',
      availability_status: 'offline',
    };

  const id = raw.id || null;
  const storeContact = id ? getContactById.value(id) : null;

  return {
    id,
    name: storeContact?.name || raw.name || raw.full_name || 'Unknown',
    thumbnail:
      storeContact?.thumbnail ||
      raw.thumbnail ||
      raw.avatar_url ||
      raw.avatar ||
      raw.profile_image_url ||
      '',
    availability_status:
      storeContact?.availability_status || raw.availability_status || 'offline',
  };
});

// Mesma historia de `resolvedContact`: estes quatro eram computed antes de virarem
// prop, e nenhum pai os passa. Com o default vazio o card nao quebra — apenas some
// com o chip de IA, o nome do responsavel, o nome da caixa e o destaque da conversa
// aberta, tudo em silencio. E `inbox` alimenta `isMessageRestricted`, o isolamento
// por agente. As props seguem valendo como override (os specs usam).
const resolvedAssignee = computed(() =>
  props.assignee && Object.keys(props.assignee).length
    ? props.assignee
    : chatMetadata.value.assignee || {}
);

const resolvedInbox = computed(() =>
  props.inbox && Object.keys(props.inbox).length
    ? props.inbox
    : getInboxById.value(props.chat.inbox_id) || {}
);

const resolvedIsActiveChat = computed(
  () => props.isActiveChat || selectedChat.value?.id === props.chat.id
);

const resolvedShowInboxName = computed(
  () =>
    !props.hideInboxName &&
    (props.showInboxName ||
      (!selectedInbox.value && (inboxesList.value?.length || 0) > 1))
);

const isPinned = computed(() => Boolean(props.chat.pinned));

// O id da caixa sai do PROPRIO chat, nao do store de caixas: `inboxes/getInbox`
// devolve `{}` quando a lista ainda nao carregou (ou quando o endpoint falha), e
// dai o submenu "Atribuir agente" pediria os agentes de `undefined` e viria vazio.
const contextMenuInboxId = computed(
  () => props.chat.inbox_id || resolvedInbox.value?.id || null
);

const conversationLink = computed(() =>
  frontendURL(
    conversationUrl({
      accountId: currentAccountId.value,
      activeInbox: selectedInbox.value,
      id: props.chat.id,
      label: props.activeLabel,
      teamId: props.teamId,
      foldersId: props.foldersId,
      conversationType: props.conversationType,
      conversationStatus: props.conversationStatus,
    })
  )
);

const hasValidContent = message => {
  if (!message) return false;
  const hasContent = String(message.content || '').trim().length > 0;
  const hasAttachments = message.attachments?.length > 0;
  return hasContent || hasAttachments || message.private === true;
};

const lastMessageInChat = computed(() => {
  const lastMessage = getLastMessage(props.chat);
  if (lastMessage) return lastMessage;

  return [
    props.chat.last_non_activity_message,
    chatMetadata.value.last_non_activity_message,
    props.chat.last_message,
    chatMetadata.value.last_message,
    props.chat.last_activity_message,
    chatMetadata.value.last_activity_message,
  ].find(hasValidContent);
});

const previewMessage = computed(() => {
  const message = lastMessageInChat.value;
  if (!message || !isMessageRestricted(message, resolvedInbox.value))
    return message;

  // ChatSPX (A4-5): o merge deixou só o cadeado. Sem o texto, o agente vê um 🔒 solto e não sabe
  // se a conversa está vazia ou restrita a outro agente. A chave já existe e está traduzida.
  return {
    ...message,
    content: `🔒 ${t('CONVERSATION.AGENT_ISOLATION.RESTRICTED_SUBTITLE')}`,
    attachments: [],
    content_attributes: {},
    content_type: 'text',
  };
});

const voiceCallData = computed(() => {
  return {
    status: props.chat.additional_attributes?.call_status,
    direction: props.chat.additional_attributes?.call_direction,
  };
});

const isAIAssignee = computed(
  () =>
    resolvedAssignee.value?.type === 'agent_bot' ||
    chatMetadata.value.assignee_type === 'AgentBot'
);

const aiChipStyle = computed(() =>
  isAIAssignee.value && resolvedAssignee.value?.id
    ? aiAccentVars(resolvedAssignee.value.id)
    : {}
);

// Quem pode marcar como lida EXPLICITAMENTE (o item do menu). Nao confundir com o
// gate de leitura implicita: abrir conversa que nao e sua deixou de limpar o "nao
// lida" (ver `may_clear_unread_marker?`). O item segue disponivel em conversa sem
// dono e da IA — e o unico jeito de zerar essas — e, em conversa com dono humano,
// so para ele.
const canMarkAsRead = computed(() => {
  const assigneeId = resolvedAssignee.value?.id;
  if (!assigneeId || isAIAssignee.value) return true;
  return Number(assigneeId) === Number(currentUser.value?.id);
});

const isUnattendedAndMine = computed(() => {
  const waitingSince =
    props.chat.waiting_since ?? chatMetadata.value.waiting_since ?? 0;
  const assigneeId = resolvedAssignee.value?.id;

  return Boolean(
    Number(waitingSince) > 0 &&
      currentUser.value?.id &&
      assigneeId &&
      !isAIAssignee.value &&
      Number(assigneeId) === Number(currentUser.value.id)
  );
});

const showMetaSection = computed(
  () =>
    resolvedShowInboxName.value ||
    (props.showAssignee && resolvedAssignee.value.name) ||
    isAIAssignee.value ||
    props.chat.priority
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !resolvedContact.value?.blocked
);

const showLabelsSection = computed(
  () => props.chat.labels?.length > 0 || hasSlaPolicyId.value
);

const messagePreviewClass = computed(() => [
  hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
  !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
  props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
]);

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, resolvedInbox.value?.id);
  } else {
    emit('deSelectConversation', props.chat.id, resolvedInbox.value?.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: onSelectConversation,
});

// O cartao navega sozinho. O `click` continua sendo emitido porque e contrato
// declarado deste componente, mas nenhum pai o escuta: quem abre a conversa e este
// `router.push`. Ctrl/Cmd+clique abre em aba nova, como em qualquer lista.
const onCardClick = event => {
  emit('click', event);
  const path = conversationLink.value;

  if (event.metaKey || event.ctrlKey) {
    window.open(
      window.chatwootConfig.hostURL + path,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }
  if (resolvedIsActiveChat.value) return;

  router?.push({ path });
};

const closeContextMenu = () => {
  emit('contextMenuToggle', false);
  showContextMenu.value = false;
  contextMenu.x = 0;
  contextMenu.y = 0;
};

const openContextMenu = event => {
  emit('contextmenu', event);
  if (!props.enableContextMenu) return;
  event.preventDefault();
  emit('contextMenuToggle', true);
  contextMenu.x = event.pageX || event.clientX;
  contextMenu.y = event.pageY || event.clientY;
  showContextMenu.value = true;
};

// O mesmo menu pelo botao de hover, ancorado no canto do botao em vez do ponteiro.
// Precisa do nextTick: o `getBoundingClientRect` so vale depois que o navegador
// aplicou a classe de hover que torna o botao visivel.
const openHoverDropdown = async event => {
  if (!props.enableContextMenu) return;
  event.preventDefault();
  event.stopPropagation();

  await nextTick();
  const buttonEl = dropdownButtonRef.value?.$el || dropdownButtonRef.value;
  if (!buttonEl?.getBoundingClientRect) return;

  const rect = buttonEl.getBoundingClientRect();
  contextMenu.x = rect.right;
  contextMenu.y = rect.bottom + 4;
  showContextMenu.value = true;
  emit('contextMenuToggle', true);
};

// Fixar e preferencia individual: so mexe na lista de quem clicou.
const togglePin = () => {
  store.dispatch('togglePin', { conversationId: props.chat.id });
};

const togglePinFromMenu = () => {
  togglePin();
  closeContextMenu();
};

const onUpdateConversation = (status, snoozedUntil) => {
  closeContextMenu();
  emit('updateConversationStatus', props.chat.id, status, snoozedUntil);
};

const onAssignAgent = agent => {
  emit('assignAgent', agent, [props.chat.id]);
  closeContextMenu();
};

const onAssignLabel = label => {
  emit('assignLabel', [label.title], [props.chat.id]);
  closeContextMenu();
};

const onRemoveLabel = label => {
  emit('removeLabel', [label.title], [props.chat.id]);
  closeContextMenu();
};

const onAssignTeam = team => {
  emit('assignTeam', team, props.chat.id);
  closeContextMenu();
};

const onMarkAsUnread = () => {
  emit('markAsUnread', props.chat.id);
  closeContextMenu();
};

const onMarkAsRead = () => {
  emit('markAsRead', props.chat.id);
  closeContextMenu();
};

const onAssignPriority = priority => {
  emit('assignPriority', priority, props.chat.id);
  closeContextMenu();
};

const onDeleteConversation = () => {
  emit('deleteConversation', props.chat.id);
  closeContextMenu();
};

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
    closeContextMenu();
  }
);
</script>

<template>
  <div
    class="icon-animated relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 cursor-pointer conversation border-b border-n-slate-3 hover:border-n-surface-1 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      'active animate-card-select bg-n-background !border-n-surface-1':
        resolvedIsActiveChat,
      'selected bg-n-slate-2 !border-n-surface-1': selected,
      'px-0': compact,
      'px-3': !compact,
      'ltr:border-l-2 rtl:border-r-2 !border-n-amber-7 bg-n-amber-5/25 ring-1 ring-n-amber-6/50 ring-inset animate-sidebar-attention motion-reduce:animate-none':
        isUnattendedAndMine && !resolvedIsActiveChat && !selected,
      'ltr:border-l-2 rtl:border-r-2 !border-n-violet-7 bg-n-violet-3/40':
        isAIAssignee &&
        !resolvedIsActiveChat &&
        !selected &&
        !isUnattendedAndMine,
    }"
    @click="onCardClick"
    @contextmenu="openContextMenu($event)"
  >
    <div
      class="relative"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="resolvedContact.name"
        :src="resolvedContact.thumbnail"
        :size="32"
        :status="resolvedContact.availability_status"
        :class="!resolvedShowInboxName ? 'mt-4' : 'mt-8'"
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{ 'ltr:ml-2 rtl:mr-2': !compact, 'mx-2': compact }"
      >
        <InboxName
          v-if="resolvedShowInboxName"
          :inbox="resolvedInbox"
          class="flex-1 min-w-0"
        />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{ 'flex-1 justify-between': !resolvedShowInboxName }"
        >
          <span
            v-if="isAIAssignee && resolvedAssignee.name"
            class="ai-chip inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-semibold leading-3 whitespace-nowrap bg-[var(--ai-bg)] text-[var(--ai-text)] dark:bg-[var(--ai-dark-bg)] dark:text-[var(--ai-dark-text)]"
            :style="aiChipStyle"
          >
            <Icon
              icon="i-lucide-sparkles"
              class="i-lucide-sparkles size-3 flex-shrink-0"
            />
            {{ resolvedAssignee.name }}
          </span>
          <span
            v-else-if="showAssignee && resolvedAssignee.name"
            class="conversation--assignee text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center gap-px truncate"
          >
            <Icon
              icon="i-lucide-user-round"
              class="i-lucide-user size-3 flex-shrink-0"
            />
            <span class="truncate">{{ resolvedAssignee.name }}</span>
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        v-if="resolvedContact"
        class="conversation--user text-sm my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="hasUnread ? 'font-semibold' : 'font-medium'"
      >
        {{ resolvedContact.name }}
      </h4>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        :message="previewMessage"
        default-empty-message=""
        class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm"
        :class="messagePreviewClass"
      />
      <p
        v-else
        class="text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
        :class="messagePreviewClass"
      >
        <Icon
          icon="i-lucide-info"
          class="size-4 -mt-0.5 align-middle inline-block"
        />
        <span class="mx-0.5">{{ $t('CHAT_LIST.NO_MESSAGES') }}</span>
      </p>
      <div
        class="absolute flex flex-col ltr:right-3 rtl:left-3"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <span class="ml-auto font-normal leading-4 text-xxs">
          <TimeAgo
            :last-activity-timestamp="
              chat.last_activity_at ||
              chat.updated_at ||
              chat.timestamp ||
              chat.created_at
            "
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="ltr:ml-auto rtl:mr-auto mt-1"
        />
        <!-- ABAIXO do relogio e do contador, nao acima: os dois botoes ficam com
             `opacity-0` no repouso, e opacidade nao devolve o espaco — colocados
             em cima, empurrariam o horario para baixo em TODO cartao, o tempo
             todo. Aqui a coluna so cresce para dentro do vazio.
             No toque nao existe hover, entao a ocultacao comeca em `md`.
             `p-0` e obrigatorio: a regra global `button { padding: .25rem .625rem }`
             (_base.scss) somada ao size-4 com box-sizing border-box zera a largura
             do conteudo, e o icone renderiza com 0px. -->
        <div class="flex items-center gap-1 ltr:ml-auto rtl:mr-auto mt-1">
          <button
            type="button"
            class="flex size-4 p-0 items-center justify-center rounded transition-opacity"
            :class="
              isPinned
                ? 'text-n-brand'
                : 'text-n-slate-10 hover:text-n-slate-12 md:opacity-0 md:group-hover:opacity-100'
            "
            :title="
              isPinned
                ? $t('CHAT_LIST.UNPIN_CONVERSATION')
                : $t('CHAT_LIST.PIN_CONVERSATION')
            "
            @click.stop="togglePin"
          >
            <!-- O tamanho vem da CLASSE, nao do `Icon`: sem componente animado
                 correspondente, o `Icon` cai num `<span class="i-lucide-pin">` e
                 o icone herdaria o `font-size` do cartao. -->
            <Icon
              :icon="isPinned ? 'i-lucide-pin-off' : 'i-lucide-pin'"
              class="size-3.5"
            />
          </button>
          <button
            v-if="enableContextMenu"
            ref="dropdownButtonRef"
            type="button"
            data-testid="conversation-card-menu-button"
            class="flex size-4 p-0 items-center justify-center rounded transition-opacity text-n-slate-10 hover:text-n-slate-12 md:opacity-0 md:group-hover:opacity-100"
            :title="$t('CONVERSATION.CARD_CONTEXT_MENU.TITLE')"
            @click.stop="openHoverDropdown($event)"
          >
            <Icon icon="i-lucide-chevron-down" />
          </button>
        </div>
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
    <!-- O `v-if` e o que monta o menu: sem ele o cartao emite `contextmenu` e nada
         acontece, que foi a regressao deste recorte. O ContextMenu de ui/ teleporta
         o conteudo para o body e fecha no blur. -->
    <ContextMenu
      v-if="showContextMenu"
      :x="contextMenu.x"
      :y="contextMenu.y"
      @close="closeContextMenu"
    >
      <ConversationContextMenu
        :status="chat.status"
        :inbox-id="contextMenuInboxId"
        :priority="chat.priority"
        :chat-id="chat.id"
        :has-unread-messages="hasUnread"
        :can-mark-as-read="canMarkAsRead"
        :conversation-labels="chat.labels"
        :conversation-url="conversationLink"
        :is-pinned="isPinned"
        :allowed-options="allowedContextMenuOptions"
        @toggle-pin="togglePinFromMenu"
        @update-conversation="onUpdateConversation"
        @assign-agent="onAssignAgent"
        @assign-label="onAssignLabel"
        @remove-label="onRemoveLabel"
        @assign-team="onAssignTeam"
        @mark-as-unread="onMarkAsUnread"
        @mark-as-read="onMarkAsRead"
        @assign-priority="onAssignPriority"
        @delete-conversation="onDeleteConversation"
        @close="closeContextMenu"
      />
    </ContextMenu>
  </div>
</template>

<style lang="scss" scoped>
.ai-chip {
  position: relative;
  overflow: hidden;
}

.ai-chip::after {
  position: absolute;
  inset: 0;
  content: '';
  background: linear-gradient(
    105deg,
    transparent 35%,
    var(--ai-shimmer, rgba(255, 255, 255, 0.35)) 50%,
    transparent 65%
  );
  transform: translateX(-100%);
  animation: ai-chip-shimmer 3.5s ease-in-out infinite;
}

@keyframes ai-chip-shimmer {
  0%,
  70%,
  100% {
    transform: translateX(-100%);
  }
  85% {
    transform: translateX(100%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .ai-chip::after {
    animation: none;
  }
}
</style>
