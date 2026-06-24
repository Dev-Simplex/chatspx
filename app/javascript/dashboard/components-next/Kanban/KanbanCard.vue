<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { formatDistanceToNowStrict } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';
import { useMapGetter } from 'dashboard/composables/store';
import { useTeamIsolation } from 'dashboard/composables/useTeamIsolation';
import { useAgentIsolation } from 'dashboard/composables/useAgentIsolation';
import { useStageColor } from './composables/useStageColor';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  conversation: {
    type: Object,
    required: true,
  },
  stageColor: {
    type: String,
    default: '#94a3b8',
  },
});

const emit = defineEmits(['move', 'schedule-message', 'remove']);

const router = useRouter();
const store = useStore();
const { t, locale } = useI18n();
const { softBg, contrastText, heatLevel, stageAgeLevel } = useStageColor();

const getContactById = useMapGetter('contacts/getContactById');
const inboxById = useMapGetter('inboxes/getInboxById');
const agentsList = useMapGetter('agents/getAgents');
const labelsGetter = useMapGetter('labels/getLabels');
const kanbanViewFilters = useMapGetter('kanban/getViewFilters');
const scheduledByConversation = useMapGetter(
  'kanban/getScheduledMessagesByConversation'
);
const { isMessageRestricted } = useTeamIsolation();
const { isMessageRestricted: isAgentMessageRestricted } = useAgentIsolation();

const dateLocale = computed(() =>
  String(locale.value || '').startsWith('pt') ? ptBR : enUS
);

const contactId = computed(() => {
  return (
    props.conversation?.contactId ||
    props.conversation?.contact_id ||
    props.conversation?.contact?.id ||
    props.conversation?.meta?.sender?.id ||
    props.conversation?.sender?.id ||
    null
  );
});

const contactFromConversation = computed(() => {
  return (
    props.conversation?.contact ||
    props.conversation?.meta?.sender ||
    props.conversation?.sender ||
    null
  );
});

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
const contactThumbnail = computed(() => {
  return (
    contact.value?.thumbnail ||
    contact.value?.avatar_url ||
    contact.value?.avatar ||
    contact.value?.profile_image_url ||
    ''
  );
});
const contactPhone = computed(
  () => contact.value?.phoneNumber || contact.value?.phone_number || ''
);

const inbox = computed(() =>
  inboxById.value(props.conversation?.inboxId || props.conversation?.inbox_id)
);

const lastMessage = computed(() => {
  const message =
    props.conversation?.lastMessage ||
    props.conversation?.last_message ||
    props.conversation?.lastNonActivityMessage ||
    props.conversation?.last_non_activity_message;

  if (
    isMessageRestricted(message, inbox.value) ||
    isAgentMessageRestricted(message, inbox.value)
  )
    return '🔒';

  return message?.content || message?.processed_message_content || '';
});

// Labels come straight from the serializer (conversation.labels: [{title,color}]).
const cardLabels = computed(() => {
  const labels = props.conversation?.labels;
  if (!Array.isArray(labels)) return [];
  return labels
    .filter(label => label && (label.title || label.name))
    .map(label => ({
      title: label.title || label.name,
      color: label.color || '#94a3b8',
    }));
});
const visibleLabels = computed(() => cardLabels.value.slice(0, 3));
const extraLabelCount = computed(() =>
  Math.max(0, cardLabels.value.length - visibleLabels.value.length)
);

// Conversation priority (urgent/high/medium/low) — native Chatwoot field.
const priority = computed(() => props.conversation?.priority || null);

// Click a label chip to filter the board by that label (Trello/Monday-style).
const resolveLabelId = title => {
  const list = labelsGetter.value;
  if (!Array.isArray(list)) return null;
  const normalized = String(title).toLowerCase();
  const found = list.find(
    label => String(label.title).toLowerCase() === normalized
  );
  return found ? Number(found.id) : null;
};
const activeLabelIds = computed(() =>
  (kanbanViewFilters.value?.labelIds || []).map(Number)
);
const isLabelActive = label => {
  const id = resolveLabelId(label.title);
  return id ? activeLabelIds.value.includes(id) : false;
};
const filterByLabel = label => {
  const id = resolveLabelId(label.title);
  if (!id) return;
  const isActive = activeLabelIds.value.includes(id);
  // Toggle: clicking the active label again clears the label filter.
  store.dispatch('kanban/setViewFilters', { labelIds: isActive ? [] : [id] });
};

const assigneeId = computed(
  () =>
    props.conversation?.assigneeId ||
    props.conversation?.assignee_id ||
    props.conversation?.meta?.assignee?.id ||
    null
);
// Optimistic override after the user reassigns from the card (0 = unassigned).
const localAssigneeId = ref(null);
const effectiveAssigneeId = computed(() =>
  localAssigneeId.value === null ? assigneeId.value : localAssigneeId.value
);
const assignee = computed(() => {
  if (!effectiveAssigneeId.value) return null;
  const list = agentsList.value;
  if (!Array.isArray(list)) return null;
  return list.find(
    agent => Number(agent.id) === Number(effectiveAssigneeId.value)
  );
});

const assignMenuOpen = ref(false);
const isAssigning = ref(false);
const agentOptions = computed(() =>
  Array.isArray(agentsList.value) ? agentsList.value : []
);
const isCurrentAssignee = agent =>
  Number(agent?.id) === Number(effectiveAssigneeId.value);

const assignTo = async agent => {
  const conversationId =
    props.conversation?.displayId ||
    props.conversation?.display_id ||
    props.conversation?.id;
  if (!conversationId || isAssigning.value) return;

  const agentId = agent?.id ?? null;
  if (Number(agentId || 0) === Number(effectiveAssigneeId.value || 0)) {
    assignMenuOpen.value = false;
    return;
  }

  isAssigning.value = true;
  try {
    await store.dispatch('assignAgent', {
      conversationId,
      agentId,
      rethrow: true,
    });
    localAssigneeId.value = agentId ? Number(agentId) : 0;
    assignMenuOpen.value = false;
    useAlert(
      agent
        ? t('KANBAN.CARD.ASSIGNED_TO', {
            name: agent.name || agent.available_name,
          })
        : t('KANBAN.CARD.UNASSIGNED_DONE')
    );
  } catch (_) {
    useAlert(t('KANBAN.CARD.ASSIGN_ERROR'));
  } finally {
    isAssigning.value = false;
  }
};

const channelIcon = computed(() => {
  const type = String(
    inbox.value?.channelType || inbox.value?.channel_type || ''
  ).toLowerCase();
  if (type.includes('whatsapp')) return 'i-ri-whatsapp-line';
  if (type.includes('telegram')) return 'i-ri-telegram-fill';
  if (type.includes('facebook') || type.includes('messenger'))
    return 'i-ri-messenger-fill';
  if (type.includes('instagram')) return 'i-ri-instagram-line';
  if (type.includes('email')) return 'i-lucide-mail';
  if (type.includes('sms') || type.includes('twilio')) return 'i-lucide-phone';
  if (type.includes('webwidget') || type.includes('web'))
    return 'i-lucide-globe';
  if (type.includes('api')) return 'i-lucide-webhook';
  return 'i-lucide-message-square';
});

const lastActivityRaw = computed(
  () =>
    props.conversation?.lastActivityAt ||
    props.conversation?.last_activity_at ||
    props.conversation?.lastMessage?.created_at ||
    props.conversation?.last_message?.created_at ||
    null
);

const lastActivityDate = computed(() => {
  const raw = lastActivityRaw.value;
  if (!raw) return null;
  const value = typeof raw === 'number' ? raw * 1000 : raw;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
});

const relativeTime = computed(() => {
  if (!lastActivityDate.value) return '';
  return formatDistanceToNowStrict(lastActivityDate.value, {
    addSuffix: true,
    locale: dateLocale.value,
  });
});

// Time idle without the "ago"/suffix — used inside aging tooltips/pills.
const idleTime = computed(() => {
  if (!lastActivityDate.value) return '';
  return formatDistanceToNowStrict(lastActivityDate.value, {
    addSuffix: false,
    locale: dateLocale.value,
  });
});

// ── Card aging (heat) — 'fresh' | 'warm' | 'cold' ────────────────────
const heat = computed(() => heatLevel(lastActivityRaw.value));
const isAging = computed(() => heat.value !== 'fresh');
const heatTitle = computed(() => {
  if (heat.value === 'cold')
    return t('KANBAN.CARD.AGING.COLD', { time: idleTime.value });
  if (heat.value === 'warm')
    return t('KANBAN.CARD.AGING.WARM', { time: idleTime.value });
  return '';
});
const heatIcon = computed(() =>
  heat.value === 'cold' ? 'i-lucide-snowflake' : 'i-lucide-alarm-clock'
);
const heatVar = computed(() =>
  heat.value === 'cold' ? 'var(--kanban-heat-cold)' : 'var(--kanban-heat-warm)'
);
const heatPillClass = computed(() =>
  heat.value === 'cold'
    ? 'bg-n-ruby-3 text-n-ruby-11'
    : 'bg-n-amber-3 text-n-amber-11'
);

// ── Time-in-stage (pipeline signal) — distinct from the idle thermometer ─
const movedAtRaw = computed(
  () => props.item?.movedAt || props.item?.moved_at || null
);
const movedAtDate = computed(() => {
  if (!movedAtRaw.value) return null;
  const value =
    typeof movedAtRaw.value === 'number'
      ? movedAtRaw.value * 1000
      : movedAtRaw.value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
});
const stageTime = computed(() => {
  if (!movedAtDate.value) return '';
  return formatDistanceToNowStrict(movedAtDate.value, {
    addSuffix: false,
    locale: dateLocale.value,
  });
});
const stageAge = computed(() => stageAgeLevel(movedAtRaw.value));
const isStuckInStage = computed(() => stageAge.value !== 'fresh');
const stageAgePillClass = computed(() =>
  stageAge.value === 'cold'
    ? 'bg-n-ruby-3 text-n-ruby-11'
    : 'bg-n-amber-3 text-n-amber-11'
);
const stageAgeTitle = computed(() =>
  t('KANBAN.CARD.STAGE_AGE.LABEL', { time: stageTime.value })
);

// ── Cover mode (Trello-style) — paints the top with the primary label ─
const primaryLabel = computed(() => cardLabels.value[0] || null);
const coverStyle = computed(() => {
  if (!primaryLabel.value) return {};
  return {
    backgroundColor: primaryLabel.value.color,
    color: contrastText(primaryLabel.value.color),
  };
});

const pendingScheduledCount = computed(() => {
  const conversationId =
    props.conversation?.id ||
    props.conversation?.displayId ||
    props.conversation?.display_id;
  if (!conversationId || typeof scheduledByConversation.value !== 'function')
    return 0;
  const messages = scheduledByConversation.value(conversationId);
  if (!Array.isArray(messages)) return 0;
  return messages.filter(
    message => (message?.status || 'pending') === 'pending'
  ).length;
});

const statusColor = computed(() => {
  const status = props.conversation?.status || 'open';
  const statusMap = {
    open: 'bg-green-600',
    pending: 'bg-yellow-500',
    resolved: 'bg-n-slate-9',
    snoozed: 'bg-blue-500',
  };
  return statusMap[status] || 'bg-n-slate-9';
});

const statusTitle = computed(() => {
  const status = props.conversation?.status || 'open';
  const statusMap = {
    open: t('KANBAN.STATUS.OPEN') || 'Aberto',
    pending: t('KANBAN.STATUS.PENDING') || 'Pendente',
    resolved: t('KANBAN.STATUS.RESOLVED') || 'Resolvido',
    snoozed: t('KANBAN.STATUS.SNOOZED') || 'Adiado',
  };
  return statusMap[status] || t('KANBAN.STATUS.OPEN') || 'Aberto';
});

const accentColor = computed(() => {
  return props.item?.stageColor || props.item?.stage_color || props.stageColor;
});

const stripGradient = computed(
  () =>
    `linear-gradient(90deg, ${accentColor.value}, ${softBg(accentColor.value, 0.5)})`
);
const cardStyleVars = computed(() => ({
  '--card-accent': accentColor.value,
  '--card-glow': softBg(accentColor.value, 0.45),
  '--card-wash': softBg(accentColor.value, 0.05),
}));

const openConversation = () => {
  const conversationId =
    props.conversation?.displayId ||
    props.conversation?.display_id ||
    props.conversation?.id ||
    props.conversationId;
  if (conversationId) {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: conversationId },
    });
  }
};

let isDragging = false;
let mouseDownTime = 0;
let mouseDownX = 0;
let mouseDownY = 0;

const handleMouseDown = event => {
  isDragging = false;
  mouseDownTime = Date.now();
  mouseDownX = event.clientX;
  mouseDownY = event.clientY;

  // Permitir que o drag and drop funcione
  const handleMouseMove = () => {
    isDragging = true;
  };

  const handleMouseUp = () => {
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
  };

  document.addEventListener('mousemove', handleMouseMove);
  document.addEventListener('mouseup', handleMouseUp);
};

const handleCardClick = event => {
  // Se foi um drag, não abrir a conversa
  if (isDragging) {
    isDragging = false;
    return;
  }

  // Verificar se foi um clique simples (não um drag)
  const timeDiff = Date.now() - mouseDownTime;
  const xDiff = Math.abs(event.clientX - mouseDownX);
  const yDiff = Math.abs(event.clientY - mouseDownY);

  if (timeDiff < 200 && xDiff < 5 && yDiff < 5) {
    openConversation();
  }
};
</script>

<template>
  <div
    class="kanban-card kanban-focusable group relative flex w-full min-w-0 flex-shrink-0 cursor-pointer flex-col overflow-hidden bg-n-solid-1"
    :class="{ 'has-cover': primaryLabel }"
    :style="cardStyleVars"
    @click="handleCardClick"
    @mousedown="handleMouseDown"
  >
    <!-- Aging heat rail (warm/cold) — left edge -->
    <div
      v-if="isAging"
      class="kanban-card__heat"
      :style="{ background: `rgb(${heatVar})` }"
      :title="heatTitle"
    />

    <!-- Cover (Trello-style) — only visible in cover mode, primary label color -->
    <div
      v-if="primaryLabel"
      class="kanban-card__cover"
      :style="coverStyle"
      :title="primaryLabel.title"
    >
      <span class="truncate">{{ primaryLabel.title }}</span>
    </div>

    <!-- Top color strip (stage accent) -->
    <div class="kanban-card__strip" :style="{ background: stripGradient }" />

    <div class="kanban-card__body flex flex-col gap-2 p-3">
      <!-- Labels (click to filter the board) -->
      <div v-if="cardLabels.length" class="flex flex-wrap items-center gap-1">
        <button
          v-for="label in visibleLabels"
          :key="label.title"
          type="button"
          class="kanban-label kanban-focusable inline-flex max-w-[124px] items-center gap-1 truncate rounded-[6px] px-1.5 py-0.5 text-[11px] font-medium leading-none text-n-slate-12 transition hover:brightness-105"
          :class="{
            'ring-1 ring-offset-1 ring-offset-n-solid-1': isLabelActive(label),
          }"
          :style="{
            backgroundColor: softBg(label.color, 0.16),
            '--tw-ring-color': label.color,
          }"
          :title="label.title"
          @click.stop="filterByLabel(label)"
        >
          <span
            class="size-1.5 shrink-0 rounded-full"
            :style="{ backgroundColor: label.color }"
          />
          <span class="truncate">{{ label.title }}</span>
        </button>
        <span
          v-if="extraLabelCount"
          class="inline-flex items-center rounded-[6px] bg-n-slate-3 px-1.5 py-0.5 text-[11px] font-medium leading-none text-n-slate-11"
        >
          {{ `+${extraLabelCount}` }}
        </span>
      </div>

      <!-- Header: contact + channel + status -->
      <div class="flex items-start justify-between gap-2">
        <div class="flex min-w-0 flex-1 items-center gap-2">
          <div class="relative shrink-0">
            <Avatar
              :name="contactName"
              :src="contactThumbnail"
              :size="32"
              rounded-full
            />
            <span
              class="kanban-card__presence absolute -bottom-0.5 -right-0.5 size-3 rounded-full ring-2 ring-n-solid-1"
              :class="statusColor"
              :title="statusTitle"
            />
          </div>
          <div class="min-w-0 flex-1">
            <h4
              class="truncate text-sm font-semibold leading-tight text-n-slate-12"
            >
              {{ contactName }}
            </h4>
            <div
              v-if="inbox"
              class="mt-0.5 flex items-center gap-1 text-n-slate-10"
            >
              <Icon :icon="channelIcon" class="size-3 shrink-0" />
              <span class="truncate text-[11px] leading-none">
                {{ inbox.name }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex shrink-0 items-center gap-1">
          <CardPriorityIcon
            v-if="priority"
            :priority="priority"
            class="kanban-card__priority"
          />
          <Icon
            icon="i-lucide-arrow-up-right"
            class="kanban-card__open size-4 text-n-slate-10 opacity-0 transition-opacity group-hover:opacity-100"
          />
        </div>
      </div>

      <!-- Last message -->
      <p
        v-if="lastMessage"
        class="kanban-card__message line-clamp-2 break-words text-[13px] leading-snug text-n-slate-11"
      >
        {{ lastMessage }}
      </p>
      <p
        v-else
        class="kanban-card__message text-[13px] italic leading-snug text-n-slate-10"
      >
        {{ t('KANBAN.ITEMS.NO_MESSAGE') }}
      </p>

      <!-- Footer: meta + actions -->
      <div
        class="flex items-center justify-between gap-2 border-t border-n-weak pt-2"
      >
        <div class="flex min-w-0 items-center gap-2 text-n-slate-10">
          <span
            v-if="relativeTime && !isAging"
            class="flex shrink-0 items-center gap-1 text-[11px]"
            :title="relativeTime"
          >
            <Icon icon="i-lucide-clock-3" class="size-3" />
            {{ relativeTime }}
          </span>
          <span
            v-else-if="isAging"
            class="flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[11px] font-medium"
            :class="heatPillClass"
            :title="heatTitle"
          >
            <Icon :icon="heatIcon" class="size-3" />
            {{ relativeTime }}
          </span>
          <span
            v-if="isStuckInStage"
            class="flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[11px] font-medium"
            :class="stageAgePillClass"
            :title="stageAgeTitle"
          >
            <Icon icon="i-lucide-hourglass" class="size-3" />
            {{ stageTime }}
          </span>
          <span
            v-if="pendingScheduledCount"
            class="flex shrink-0 items-center gap-1 rounded-full bg-n-teal-3 px-1.5 py-0.5 text-[11px] font-medium text-n-teal-11"
            :title="t('KANBAN.SCHEDULED_MESSAGES.TITLE')"
          >
            <Icon icon="i-lucide-send" class="size-3" />
            {{ pendingScheduledCount }}
          </span>
          <span
            v-if="contactPhone"
            class="min-w-0 truncate font-mono text-[11px] text-n-slate-11"
            :title="contactPhone"
          >
            {{ contactPhone }}
          </span>
        </div>

        <div class="flex shrink-0 items-center gap-2">
          <!-- Assignee picker -->
          <div class="relative" @click.stop>
            <button
              type="button"
              class="kanban-focusable flex items-center rounded-full transition hover:opacity-80"
              :title="
                assignee
                  ? assignee.name || assignee.available_name
                  : t('KANBAN.CARD.UNASSIGNED')
              "
              :aria-label="
                assignee
                  ? assignee.name || assignee.available_name
                  : t('KANBAN.CARD.UNASSIGNED')
              "
              aria-haspopup="listbox"
              :aria-expanded="assignMenuOpen"
              :disabled="isAssigning"
              @click="assignMenuOpen = !assignMenuOpen"
            >
              <Avatar
                v-if="assignee"
                :name="assignee.name || assignee.available_name"
                :src="assignee.thumbnail || assignee.avatar_url"
                :size="20"
                rounded-full
                class="ring-1 ring-n-weak"
              />
              <span
                v-else
                class="flex size-5 items-center justify-center rounded-full border border-dashed border-n-slate-6 bg-n-slate-2 text-n-slate-9"
              >
                <Icon icon="i-lucide-user" class="size-3" />
              </span>
            </button>

            <template v-if="assignMenuOpen">
              <div class="fixed inset-0 z-20" @click="assignMenuOpen = false" />
              <div
                role="listbox"
                :aria-label="t('KANBAN.CARD.UNASSIGNED')"
                class="absolute bottom-7 right-0 z-30 max-h-56 w-52 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
              >
                <button
                  type="button"
                  role="option"
                  :aria-selected="!effectiveAssigneeId"
                  class="kanban-focusable flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs text-n-slate-11 transition-colors hover:bg-n-alpha-1"
                  @click="assignTo(null)"
                >
                  <span
                    class="flex size-5 items-center justify-center rounded-full bg-n-slate-3 text-n-slate-9"
                  >
                    <Icon icon="i-lucide-user-x" class="size-3" />
                  </span>
                  {{ t('KANBAN.CARD.UNASSIGNED') }}
                </button>
                <button
                  v-for="agent in agentOptions"
                  :key="agent.id"
                  type="button"
                  role="option"
                  :aria-selected="isCurrentAssignee(agent)"
                  class="kanban-focusable flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs text-n-slate-12 transition-colors hover:bg-n-alpha-1"
                  @click="assignTo(agent)"
                >
                  <Avatar
                    :name="agent.name || agent.available_name"
                    :src="agent.thumbnail || agent.avatar_url"
                    :size="20"
                    rounded-full
                  />
                  <span class="truncate">
                    {{ agent.name || agent.available_name }}
                  </span>
                  <Icon
                    v-if="isCurrentAssignee(agent)"
                    icon="i-lucide-check"
                    class="ml-auto size-3.5 text-n-teal-11"
                  />
                </button>
              </div>
            </template>
          </div>

          <div
            class="flex items-center gap-1 opacity-100 transition-opacity duration-200 md:opacity-0 md:group-hover:opacity-100"
            @click.stop
          >
            <Button
              size="xs"
              variant="ghost"
              icon="i-lucide-clock"
              :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
              :aria-label="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
              class="kanban-focusable !h-6 !w-6 !p-0 hover:bg-n-blue-3 hover:text-n-blue-11"
              @click="emit('schedule-message', conversation)"
            />
            <Button
              size="xs"
              variant="ghost"
              icon="i-lucide-move"
              :title="t('KANBAN.ITEMS.MOVE')"
              :aria-label="t('KANBAN.ITEMS.MOVE')"
              class="kanban-focusable !h-6 !w-6 !p-0 hover:bg-n-teal-3 hover:text-n-teal-11"
              @click="emit('move', item)"
            />
            <Button
              size="xs"
              variant="ghost"
              icon="i-lucide-x"
              :title="t('KANBAN.ITEMS.REMOVE')"
              :aria-label="t('KANBAN.ITEMS.REMOVE')"
              class="kanban-focusable !h-6 !w-6 !p-0 hover:bg-n-ruby-3 hover:text-n-ruby-11"
              @click="emit('remove', item)"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.kanban-card {
  border: 1px solid rgb(var(--border-weak));
  border-radius: var(--kanban-card-radius);
  box-shadow: var(--kanban-card-shadow);
  transition:
    box-shadow 0.18s ease,
    transform 0.18s var(--kanban-spring, ease),
    border-color 0.18s ease;
}

.kanban-card:hover {
  transform: translateY(-3px);
  border-color: var(--card-accent, rgb(var(--border-weak)));
  box-shadow:
    0 12px 24px -12px var(--card-glow, transparent),
    var(--kanban-card-shadow-hover);
}

.kanban-card:active {
  transform: translateY(-1px) scale(0.997);
}

/* Aging heat rail — thin colored bar on the leading edge */
.kanban-card__heat {
  position: absolute;
  inset-block: 0;
  inset-inline-start: 0;
  width: 3px;
  z-index: 2;
  pointer-events: none;
}

/* Cover (Trello-style) — hidden unless the board is in cover mode */
.kanban-card__cover {
  display: none;
  align-items: center;
  min-height: 1.75rem;
  padding: 0.25rem 0.625rem;
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
  flex-shrink: 0;
}

/* Faint stage-tinted wash that blooms in on hover */
.kanban-card::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(
    180deg,
    var(--card-wash, transparent),
    transparent 60%
  );
  opacity: 0;
  transition: opacity 0.18s ease;
}

.kanban-card:hover::after {
  opacity: 1;
}

.kanban-card__strip {
  height: 5px;
  width: 100%;
  flex-shrink: 0;
}

.kanban-card__body {
  position: relative;
  z-index: 1;
}

.kanban-card__presence {
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.04);
}

/* Reuse the conversation-list priority icon, sized down for the card. */
.kanban-card__priority :deep(svg) {
  width: 16px;
  height: 16px;
}
</style>
