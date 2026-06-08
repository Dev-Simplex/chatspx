<script setup>
// KanbanCard redesenhado (P1-02) com anatomia CRM-WhatsApp:
//   - Borda esquerda 3px com cor da stage
//   - Linha 1: avatar (32px) + nome + ícone do canal
//   - Linha 2: preview msg (1 linha, truncate)
//   - Linha 3: aging + atendente + tags + badge unread
// Drag via PDND (P1-07). Click abre conversa.
// Sem CSS scoped (Tailwind only). Altura visual <= 120px.
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useTeamIsolation } from 'dashboard/composables/useTeamIsolation';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useKanbanMessagePreview } from 'dashboard/composables/kanban/useKanbanMessagePreview';
import { makeKanbanCardDraggable } from 'dashboard/composables/kanban/useKanbanDrag';
import { useKanbanAging } from 'dashboard/composables/kanban/useKanbanAging';
import { useKanbanBoardStore } from 'dashboard/store/pinia/kanban/board';
import KanbanCardReply from './KanbanCardReply.vue';
import KanbanCaptainSuggestion from './KanbanCaptainSuggestion.vue';

const props = defineProps({
  item: { type: Object, required: true },
  conversation: { type: Object, required: true },
  stage: { type: Object, default: () => ({}) },
  stageColor: { type: String, default: '#94a3b8' },
  stageName: { type: String, default: '' },
  index: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
  // P2-07: bulk mode (mostra checkbox)
  bulkMode: { type: Boolean, default: false },
  // P2-03: drawer in side. Quando true, click emite "open-drawer" em vez de navegar.
  openInDrawer: { type: Boolean, default: true },
});

// eslint-disable-next-line vue/custom-event-name-casing -- kebab kept for legacy parent listeners
const emit = defineEmits(['move', 'schedule-message', 'remove', 'open-drawer']);

const router = useRouter();
const boardStore = useKanbanBoardStore();
const { t } = useI18n();
const getContactById = useMapGetter('contacts/getContactById');
const inboxById = useMapGetter('inboxes/getInboxById');
const { isMessageRestricted } = useTeamIsolation();
const { getMessagePreview } = useKanbanMessagePreview();

const cardEl = ref(null);
const showQuickReply = ref(false);

const funnelIdForCard = computed(
  () =>
    props.item?.funnelId ||
    props.item?.funnel_id ||
    props.item?.kanbanId ||
    props.item?.kanban_id ||
    boardStore.activeKanbanId ||
    null
);

const openQuickReply = e => {
  e?.preventDefault?.();
  e?.stopPropagation?.();
  showQuickReply.value = true;
};

const closeQuickReply = () => {
  showQuickReply.value = false;
};

makeKanbanCardDraggable(cardEl, {
  itemId: Number(props.item?.id),
  stageId: Number(props.item?.funnelStageId || props.item?.funnel_stage_id),
});

const contactId = computed(
  () =>
    props.conversation?.contactId ||
    props.conversation?.contact_id ||
    props.conversation?.contact?.id ||
    props.conversation?.meta?.sender?.id ||
    props.conversation?.sender?.id ||
    null
);

const contactFromConversation = computed(
  () =>
    props.conversation?.contact ||
    props.conversation?.meta?.sender ||
    props.conversation?.sender ||
    null
);

const contactFromStore = computed(() => {
  if (!contactId.value) return null;
  const getter = getContactById.value;
  if (typeof getter !== 'function') return null;
  return getter(contactId.value);
});

const contact = computed(
  () => contactFromConversation.value || contactFromStore.value || null
);

const contactName = computed(
  () => contact.value?.name || t('KANBAN.ITEMS.UNNAMED_CONTACT')
);

const contactThumbnail = computed(
  () =>
    contact.value?.thumbnail ||
    contact.value?.avatar_url ||
    contact.value?.avatar ||
    ''
);

const inbox = computed(() =>
  inboxById.value(props.conversation?.inboxId || props.conversation?.inbox_id)
);

const lastMessageRaw = computed(
  () =>
    props.conversation?.lastMessage ||
    props.conversation?.last_message ||
    props.conversation?.lastNonActivityMessage ||
    props.conversation?.last_non_activity_message
);

const preview = computed(() => {
  if (isMessageRestricted(lastMessageRaw.value, inbox.value)) {
    return { text: '🔒', isPlaceholder: true, outgoing: false };
  }
  return getMessagePreview(lastMessageRaw.value, t);
});

const channelType = computed(() => {
  const type = inbox.value?.channel_type || inbox.value?.channelType || '';
  // ex.: "Channel::Api" -> "api"
  const last = type.split('::').pop();
  return (last || '').toLowerCase();
});

const channelIcon = computed(() => {
  switch (channelType.value) {
    case 'whatsapp':
      return 'i-lucide-message-circle';
    case 'facebook':
      return 'i-lucide-facebook';
    case 'instagram':
      return 'i-lucide-instagram';
    case 'email':
      return 'i-lucide-mail';
    case 'sms':
      return 'i-lucide-smartphone';
    case 'telegram':
      return 'i-lucide-send';
    case 'twitter':
      return 'i-lucide-twitter';
    case 'line':
      return 'i-lucide-message-square';
    case 'api':
    case 'webwidget':
    default:
      return 'i-lucide-globe';
  }
});

const channelLabel = computed(() => {
  const map = {
    whatsapp: 'WhatsApp',
    facebook: 'Facebook',
    instagram: 'Instagram',
    email: 'Email',
    sms: 'SMS',
    telegram: 'Telegram',
    twitter: 'Twitter',
    line: 'Line',
    api: 'API',
    webwidget: 'Web',
  };
  return map[channelType.value] || (channelType.value || '').toUpperCase();
});

const unreadCount = computed(
  () =>
    Number(
      props.conversation?.unreadCount ?? props.conversation?.unread_count ?? 0
    ) || 0
);

const unreadLabel = computed(() => {
  const n = unreadCount.value;
  return n >= 10 ? '9+' : String(n);
});

const assignee = computed(
  () =>
    props.conversation?.assignee || props.conversation?.meta?.assignee || null
);

const labels = computed(() => {
  const ls = props.conversation?.labels || props.conversation?.labelList || [];
  return Array.isArray(ls) ? ls.slice(0, 3) : [];
});

const remainingLabels = computed(() => {
  const ls = props.conversation?.labels || props.conversation?.labelList || [];
  return Array.isArray(ls) && ls.length > 3 ? ls.length - 3 : 0;
});

// KANBAN-P2-02: aging visual / deal rotting.
// Usa last_stage_change_at (do item) + rot_after_days (da stage).
const stageRef = computed(() => props.stage || {});
const { daysInStage, level: agingLevel } = useKanbanAging(
  computed(() => props.item),
  stageRef
);

const stageAgingClasses = computed(() => {
  switch (agingLevel.value) {
    case 'rotting':
      return 'bg-ruby-100 text-ruby-700 dark:bg-ruby-900/40 dark:text-ruby-300';
    case 'warning':
      return 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300';
    default:
      return 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300';
  }
});

const stageAgingIcon = computed(() => {
  if (agingLevel.value === 'rotting') return 'i-lucide-clock-alert';
  if (agingLevel.value === 'warning') return 'i-lucide-clock';
  return null;
});

const stageAgingText = computed(() => {
  const d = daysInStage.value;
  if (d <= 0) return t('KANBAN.CARD.AGING_TODAY');
  return t('KANBAN.CARD.AGING_DAYS', { days: d });
});

const stageAgingAria = computed(() =>
  t('KANBAN.CARD.STAGE_AGING_ARIA', {
    days: daysInStage.value,
    level: agingLevel.value,
  })
);

const stageBorderColor = computed(
  () =>
    props.item?.stageColor ||
    props.item?.stage_color ||
    props.stageColor ||
    '#94a3b8'
);

// DoD §35 / P3-06: card mostra R$ valor + probability% quando definidos.
const brlFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const valueDisplay = computed(() => {
  const cents = Number(
    props.item?.metadata?.value_cents ?? props.item?.metadata?.valueCents ?? 0
  );
  if (!cents || cents <= 0) return null;
  return brlFormatter.format(cents / 100);
});

const probabilityDisplay = computed(() => {
  const p = props.stage?.probability;
  if (p == null || p === '') return null;
  const n = Number(p);
  if (!Number.isFinite(n)) return null;
  return `${n}%`;
});

const valueAriaLabel = computed(() =>
  valueDisplay.value
    ? t('KANBAN.CARD.VALUE_LABEL', { value: valueDisplay.value })
    : null
);

const probabilityAriaLabel = computed(() =>
  probabilityDisplay.value
    ? t('KANBAN.CARD.PROBABILITY_LABEL', { value: probabilityDisplay.value })
    : null
);

const ariaLabel = computed(() =>
  t('KANBAN.CARD.ARIA_LABEL', {
    name: contactName.value,
    stage: props.stageName || '',
    index: props.index + 1,
    total: props.total,
  })
);

const isSelected = computed(() =>
  boardStore.selectedItemIds.includes(Number(props.item?.id))
);

const toggleSelection = () => {
  boardStore.toggleSelectItem(Number(props.item?.id));
};

const openConversation = e => {
  if (e?.defaultPrevented) return;
  if (props.bulkMode) {
    toggleSelection();
    return;
  }
  // Shift+Click ativa bulk mode (P2-07).
  if (e?.shiftKey) {
    toggleSelection();
    return;
  }
  if (props.openInDrawer) {
    // eslint-disable-next-line vue/custom-event-name-casing
    emit('open-drawer', props.item);
    return;
  }
  const conversationId =
    props.conversation?.displayId ||
    props.conversation?.display_id ||
    props.conversation?.id;
  if (!conversationId) return;
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};
</script>

<template>
  <article
    ref="cardEl"
    role="button"
    tabindex="0"
    :aria-label="ariaLabel"
    :aria-pressed="isSelected"
    class="group relative flex w-full min-w-0 flex-col gap-2 rounded-lg border bg-white dark:bg-slate-900 px-3 py-2.5 cursor-pointer hover:shadow-md transition-shadow focus:outline-none focus:ring-2 focus:ring-iris-500 border-l-[3px]"
    :class="
      isSelected
        ? 'border-iris-500 bg-iris-50 dark:bg-iris-900/20'
        : 'border-slate-200 dark:border-slate-700'
    "
    :style="{ borderLeftColor: stageBorderColor }"
    @click="openConversation"
    @keydown.enter.prevent="openConversation"
    @keydown.space.prevent="openConversation"
  >
    <input
      v-if="bulkMode"
      type="checkbox"
      class="absolute top-2 right-2 size-4 rounded text-iris-600 focus:ring-iris-500"
      :checked="isSelected"
      :aria-label="t('KANBAN.BULK.TOGGLE')"
      @click.stop="toggleSelection"
    />
    <!-- Linha 1: avatar + nome + canal -->
    <div class="flex items-center gap-2 min-w-0">
      <div class="relative flex-shrink-0">
        <Avatar
          :name="contactName"
          :src="contactThumbnail"
          :size="32"
          rounded-full
        />
        <span
          v-if="unreadCount > 0"
          class="absolute -top-1 -right-1 min-w-[16px] h-[16px] px-1 rounded-full bg-red-500 text-white text-[10px] font-bold flex items-center justify-center leading-none"
          :aria-label="t('KANBAN.CARD.UNREAD_LABEL', { count: unreadCount })"
        >
          {{ unreadLabel }}
        </span>
      </div>

      <h4
        class="flex-1 min-w-0 truncate text-sm font-medium text-slate-900 dark:text-white"
      >
        {{ contactName }}
      </h4>

      <span
        :title="t('KANBAN.CARD.CHANNEL_TOOLTIP', { channel: channelLabel })"
        :aria-label="
          t('KANBAN.CARD.CHANNEL_TOOLTIP', { channel: channelLabel })
        "
        class="text-slate-400 dark:text-slate-500 flex-shrink-0"
      >
        <Icon :icon="channelIcon" class="size-4" />
      </span>
    </div>

    <!-- Linha 2: preview da mensagem -->
    <p
      class="text-[13px] leading-snug text-slate-600 dark:text-slate-300 truncate"
      :class="{ italic: preview.isPlaceholder }"
    >
      <span v-if="preview.outgoing" class="italic text-slate-500">{{
        t('KANBAN.CARD.PREVIEW_OUTGOING_PREFIX')
      }}</span>
      <span>{{ preview.text }}</span>
    </p>

    <!-- DoD §35 / P3-06: valor estimado + probability -->
    <div
      v-if="valueDisplay || probabilityDisplay"
      class="flex items-center gap-2 text-xs mt-0.5"
    >
      <span
        v-if="valueDisplay"
        class="font-semibold text-emerald-600 dark:text-emerald-400"
        :aria-label="valueAriaLabel"
        :title="valueAriaLabel"
      >
        {{ valueDisplay }}
      </span>
      <span
        v-if="probabilityDisplay"
        class="text-slate-500 dark:text-slate-400"
        :aria-label="probabilityAriaLabel"
        :title="probabilityAriaLabel"
      >
        {{ probabilityDisplay }}
      </span>
    </div>

    <!-- Linha 3: aging + atendente + tags + ações hover -->
    <div class="flex items-center gap-2 text-xs min-w-0">
      <span
        :aria-label="stageAgingAria"
        :title="stageAgingAria"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full font-medium flex-shrink-0"
        :class="stageAgingClasses"
      >
        <Icon
          v-if="stageAgingIcon"
          :icon="stageAgingIcon"
          class="size-3"
          aria-hidden="true"
        />
        {{ stageAgingText }}
      </span>

      <Avatar
        v-if="assignee"
        :name="assignee.name || assignee.available_name"
        :src="assignee.thumbnail || assignee.avatar_url"
        :size="20"
        rounded-full
        class="flex-shrink-0"
      />

      <div class="flex items-center gap-1 min-w-0 flex-1">
        <span
          v-for="label in labels"
          :key="label.id"
          class="inline-block px-1.5 py-0.5 rounded-full text-[10px] font-medium truncate max-w-[80px]"
          :style="{
            background: `${label.color || '#94a3b8'}22`,
            color: label.color || '#475569',
          }"
        >
          {{ label.title || label.name }}
        </span>
        <span
          v-if="remainingLabels > 0"
          class="text-[10px] text-slate-500 dark:text-slate-400 font-medium flex-shrink-0"
        >
          {{ t('KANBAN.CARD.MORE_TAGS', { count: remainingLabels }) }}
        </span>
      </div>

      <div
        class="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0"
        @click.stop
      >
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-iris-600 transition-colors"
          :aria-label="t('KANBAN.CARD.ACTION_QUICK_REPLY')"
          :title="t('KANBAN.CARD.ACTION_QUICK_REPLY')"
          @click.stop="openQuickReply"
        >
          <Icon icon="i-lucide-corner-down-left" class="size-3.5" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-iris-600 transition-colors"
          :aria-label="t('KANBAN.CARD.ACTION_SCHEDULE')"
          :title="t('KANBAN.CARD.ACTION_SCHEDULE')"
          @click="emit('schedule-message', conversation)"
        >
          <Icon icon="i-lucide-clock" class="size-3.5" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-teal-600 transition-colors"
          :aria-label="t('KANBAN.CARD.ACTION_ASSIGN')"
          :title="t('KANBAN.CARD.ACTION_ASSIGN')"
          @click="emit('move', item)"
        >
          <Icon icon="i-lucide-move" class="size-3.5" />
        </button>
        <button
          type="button"
          class="inline-flex items-center justify-center size-6 rounded-md text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-ruby-600 transition-colors"
          :aria-label="t('KANBAN.CARD.ACTION_DELETE')"
          :title="t('KANBAN.CARD.ACTION_DELETE')"
          @click="emit('remove', item)"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </div>
    </div>

    <!-- P3-02: sugestão Captain AI Triage -->
    <KanbanCaptainSuggestion
      v-if="
        item?.metadata?.captain_classification &&
        !item?.metadata?.captain_classification?.feedback
      "
      :item="item"
      :funnel-id="funnelIdForCard"
      :stages="boardStore.stagesOf(funnelIdForCard)"
      @click.stop
    />

    <!-- P3-01: mini-composer in-card -->
    <KanbanCardReply
      v-if="showQuickReply"
      :funnel-id="funnelIdForCard"
      :item-id="item?.id"
      :contact-name="contactName"
      @close="closeQuickReply"
      @sent="closeQuickReply"
    />
  </article>
</template>
