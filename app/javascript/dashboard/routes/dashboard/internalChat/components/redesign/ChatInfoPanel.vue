<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AutoAlertsAPI from 'dashboard/api/internalChatAutoAlerts';
import { lastSeenText } from './lastSeen';
import SharedMediaTabs from './SharedMediaTabs.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
  canManage: { type: Boolean, default: false },
  // Minhas mensagens favoritas desta conversa: { items, state }.
  starred: { type: Object, default: () => ({ items: [], state: 'idle' }) },
});

defineEmits([
  'close',
  'manage',
  'search',
  'toggleMute',
  'favorite',
  'openMessage',
  'retryStarred',
]);

const { t } = useI18n();
const PRESENCES = ['online', 'busy', 'offline'];
const labelFor = presence =>
  t(
    `INTERNAL_CHAT.PRESENCE.${(PRESENCES.includes(presence) ? presence : 'offline').toUpperCase()}`
  );

const online = computed(() => props.conversation.presence === 'online');
const headerStatus = computed(() => {
  const count = props.conversation.members?.length || 0;
  const params = {
    count,
    online: (props.conversation.members || []).filter(
      m => m.presence === 'online'
    ).length,
  };
  if (props.conversation.isTeam) {
    return t('INTERNAL_CHAT.HEADER.TEAM_MEMBERS_ONLINE', params);
  }
  if (props.conversation.isGroup) {
    return t('INTERNAL_CHAT.HEADER.MEMBERS_ONLINE', params);
  }
  // DM → presença do colega; fora do ar, quando foi visto por último.
  if ((props.conversation.presence || 'offline') === 'offline')
    return lastSeenText(t, props.conversation.lastSeenAt);
  return labelFor(props.conversation.presence);
});

// Grupo de time pode ter muita gente: acima de 8, busca por nome.
const MEMBER_SEARCH_MIN = 8;
const memberQuery = ref('');
watch(
  () => props.conversation.id,
  () => {
    memberQuery.value = '';
  }
);
const RANK = { online: 0, busy: 1, offline: 2 };
const members = computed(() =>
  (props.conversation.members || [])
    .map(m => {
      const presence = m.presence || 'offline';
      return {
        id: m.id,
        name: m.name,
        avatarSrc: m.avatar_url || '',
        isMe: m.id === props.currentUserId,
        status: presence, // dot no Avatar
        online: presence === 'online',
        label:
          presence === 'offline'
            ? lastSeenText(t, m.lastSeenAt)
            : labelFor(presence),
        rank: RANK[presence] ?? 2,
      };
    })
    // quem está online primeiro; você por último
    .sort((a, b) => a.isMe - b.isMe || a.rank - b.rank)
);
const visibleMembers = computed(() => {
  const q = memberQuery.value.trim().toLowerCase();
  if (!q) return members.value;
  return members.value.filter(m => (m.name || '').toLowerCase().includes(q));
});

// Mensagens favoritas: busca acima de 8.
const starQuery = ref('');
watch(
  () => props.conversation.id,
  () => {
    starQuery.value = '';
  }
);
const starPreview = m =>
  m.content ||
  `📎 ${(m.attachments || []).map(a => a.filename).join(', ') || t('INTERNAL_CHAT.ATTACHMENT')}`;
const visibleStarred = computed(() => {
  const q = starQuery.value.trim().toLowerCase();
  const items = props.starred.items || [];
  if (!q) return items;
  return items.filter(m =>
    `${m.user?.name || ''} ${starPreview(m)}`.toLowerCase().includes(q)
  );
});
const starDate = ts =>
  ts
    ? new Date(ts * 1000).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';

// Avisos automáticos (só sala de time): o servidor diz o que está ligado e se eu posso mudar.
const ALERT_EVENTS = ['lead_parado', 'meta_batida'];
const alerts = ref(null);
const alertsState = ref('idle'); // idle | loading | saving | saved | error

const loadAlerts = async () => {
  alerts.value = null;
  if (!props.conversation.isTeam) return;
  alertsState.value = 'loading';
  try {
    const { data } = await AutoAlertsAPI.get(props.conversation.id);
    alerts.value = data;
    alertsState.value = 'idle';
  } catch {
    alertsState.value = 'error';
  }
};
watch(() => props.conversation.id, loadAlerts, { immediate: true });

const toggleAlert = async (event, value) => {
  const previous = alerts.value.events[event];
  alerts.value.events[event] = value;
  alertsState.value = 'saving';
  try {
    const { data } = await AutoAlertsAPI.update(props.conversation.id, {
      [event]: value,
    });
    alerts.value = data;
    alertsState.value = 'saved';
  } catch {
    alerts.value.events[event] = previous;
    alertsState.value = 'error';
  }
};
</script>

<template>
  <div class="flex flex-col h-full bg-n-solid-1">
    <header
      class="flex items-center flex-shrink-0 h-16 gap-2 px-4 border-b border-n-weak"
    >
      <h3 class="flex-1 mb-0 text-base font-semibold text-n-slate-12">
        {{ t('INTERNAL_CHAT.INFO.TITLE') }}
      </h3>
      <button
        v-tooltip="t('INTERNAL_CHAT.INFO.CLOSE')"
        type="button"
        class="inline-flex items-center justify-center rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('INTERNAL_CHAT.INFO.CLOSE')"
        @click="$emit('close')"
      >
        <span class="size-5 i-lucide-x" />
      </button>
    </header>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <!-- Cartão de quem é (como o "Detalhes" do iPhone) + ações rápidas -->
      <div class="flex flex-col items-center gap-1 px-4 pt-6 pb-5">
        <Avatar
          :name="conversation.name"
          :src="conversation.avatarSrc || ''"
          :icon-name="conversation.iconName"
          :size="88"
          :status="conversation.isGroup ? null : conversation.presence"
          rounded-full
        />
        <h2
          class="mt-2 text-lg font-bold leading-tight text-center text-n-slate-12"
        >
          {{ conversation.name }}
        </h2>
        <p
          class="mb-0 text-[13px] text-center"
          :class="online ? 'text-n-teal-11 font-medium' : 'text-n-slate-11'"
        >
          {{ headerStatus }}
        </p>
        <div class="grid w-full grid-cols-3 gap-2 mt-4">
          <button
            type="button"
            class="flex flex-col items-center gap-1 py-2.5 text-xs font-medium transition-colors rounded-2xl bg-n-alpha-1 hover:bg-n-alpha-2 text-n-teal-11"
            @click="$emit('search')"
          >
            <span class="text-lg i-lucide-search" />
            {{ t('INTERNAL_CHAT.INFO.SEARCH') }}
          </button>
          <button
            v-if="!conversation.readOnly"
            type="button"
            class="flex flex-col items-center gap-1 py-2.5 text-xs font-medium transition-colors rounded-2xl bg-n-alpha-1 hover:bg-n-alpha-2 text-n-teal-11"
            :aria-pressed="conversation.muted"
            @click="$emit('toggleMute')"
          >
            <span
              class="text-lg"
              :class="
                conversation.muted ? 'i-lucide-bell' : 'i-lucide-bell-off'
              "
            />
            {{
              conversation.muted
                ? t('INTERNAL_CHAT.INFO.UNMUTE')
                : t('INTERNAL_CHAT.INFO.MUTE')
            }}
          </button>
          <button
            type="button"
            class="flex flex-col items-center gap-1 py-2.5 text-xs font-medium transition-colors rounded-2xl bg-n-alpha-1 hover:bg-n-alpha-2 text-n-teal-11"
            :aria-pressed="conversation.favorited"
            @click="$emit('favorite')"
          >
            <span
              class="text-lg"
              :class="
                conversation.favorited ? 'i-lucide-star-off' : 'i-lucide-star'
              "
            />
            {{
              conversation.favorited
                ? t('INTERNAL_CHAT.INFO.UNFAVORITE')
                : t('INTERNAL_CHAT.INFO.FAVORITE')
            }}
          </button>
        </div>
        <button
          v-if="canManage"
          type="button"
          class="flex items-center justify-center w-full gap-1.5 py-2 mt-2 text-xs font-semibold transition-colors rounded-2xl text-n-slate-12 bg-n-alpha-1 hover:bg-n-alpha-2"
          @click="$emit('manage')"
        >
          <span class="i-lucide-settings-2" />
          {{ t('INTERNAL_CHAT.MANAGE.TITLE') }}
        </button>
      </div>

      <!-- Mensagens favoritas (só suas) -->
      <div class="px-3 pb-3">
        <p
          class="flex items-center gap-1.5 px-1 mb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
        >
          <span class="flex-shrink-0 i-ph-star-fill size-3.5 text-n-amber-9" />
          {{ t('INTERNAL_CHAT.STARRED.TITLE') }}
          <span v-if="starred.items.length" class="font-normal">
            {{ starred.items.length }}
          </span>
        </p>
        <p
          v-if="starred.state === 'loading' && !starred.items.length"
          class="flex items-center justify-center gap-2 px-3 py-4 mb-0 text-xs rounded-2xl bg-n-alpha-1 text-n-slate-11"
        >
          <span class="i-lucide-loader-circle animate-spin" />
          {{ t('INTERNAL_CHAT.LOADING') }}
        </p>
        <div
          v-else-if="starred.state === 'error' && !starred.items.length"
          class="flex flex-col items-center gap-2 px-3 py-4 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-11"
        >
          {{ t('INTERNAL_CHAT.STARRED.ERROR') }}
          <button
            type="button"
            class="px-3 py-1 font-semibold rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
            @click="$emit('retryStarred')"
          >
            {{ t('INTERNAL_CHAT.RETRY') }}
          </button>
        </div>
        <p
          v-else-if="!starred.items.length"
          class="px-3 py-4 mb-0 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.STARRED.EMPTY') }}
        </p>
        <template v-else>
          <div v-if="starred.items.length > 8" class="relative px-1 mb-1.5">
            <span
              class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-4 top-1/2 text-n-slate-10"
            />
            <input
              v-model="starQuery"
              type="text"
              :placeholder="t('INTERNAL_CHAT.STARRED.SEARCH')"
              :aria-label="t('INTERNAL_CHAT.STARRED.SEARCH')"
              class="reset-base w-full h-9 pl-9 pr-3 text-sm border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
            />
          </div>
          <p
            v-if="!visibleStarred.length"
            class="px-3 py-4 mb-0 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
          >
            {{ t('INTERNAL_CHAT.NO_RESULTS') }}
          </p>
          <div v-else class="overflow-hidden rounded-2xl bg-n-alpha-1">
            <button
              v-for="m in visibleStarred"
              :key="m.id"
              v-tooltip.left="t('INTERNAL_CHAT.STARRED.OPEN')"
              type="button"
              class="flex flex-col w-full gap-0.5 px-3 py-2 text-left border-b border-solid last:border-b-0 border-n-weak hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
              @click="$emit('openMessage', m.id)"
            >
              <span class="flex items-center justify-between gap-2 text-xs">
                <span class="font-semibold truncate text-n-slate-12">
                  {{ m.user?.name }}
                </span>
                <span class="flex-shrink-0 tabular-nums text-n-slate-10">
                  {{ starDate(m.created_at) }}
                </span>
              </span>
              <span
                class="text-[13px] leading-snug line-clamp-2 text-n-slate-11"
              >
                {{ starPreview(m) }}
              </span>
            </button>
          </div>
        </template>
      </div>

      <!-- Mídia, links e docs da conversa -->
      <div class="px-3 pb-3">
        <SharedMediaTabs
          :channel-id="conversation.id"
          :last-at="conversation.lastAt || 0"
          @open-message="$emit('openMessage', $event)"
        />
      </div>

      <!-- Avisos automáticos da sala do time -->
      <div v-if="conversation.isTeam" class="px-3 pb-3">
        <p
          class="px-1 mb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.AUTO_ALERTS.TITLE') }}
        </p>
        <div v-if="alerts" class="overflow-hidden rounded-2xl bg-n-alpha-1">
          <div
            v-for="event in ALERT_EVENTS"
            :key="event"
            class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-n-weak"
          >
            <span class="flex-1 min-w-0">
              <span class="block text-sm font-medium text-n-slate-12">
                {{ t(`INTERNAL_CHAT.AUTO_ALERTS.${event.toUpperCase()}.NAME`) }}
              </span>
              <span class="block text-xs leading-snug text-n-slate-11">
                {{
                  t(`INTERNAL_CHAT.AUTO_ALERTS.${event.toUpperCase()}.HINT`, {
                    minutes: alerts.limiar_minutos,
                  })
                }}
              </span>
            </span>
            <span class="flex items-center gap-2 pt-0.5">
              <span
                class="text-[11px]"
                :class="
                  alerts.events[event] ? 'text-n-teal-11' : 'text-n-slate-10'
                "
              >
                {{
                  alerts.events[event]
                    ? t('INTERNAL_CHAT.AUTO_ALERTS.ON')
                    : t('INTERNAL_CHAT.AUTO_ALERTS.OFF')
                }}
              </span>
              <Switch
                v-if="alerts.can_manage"
                :model-value="alerts.events[event]"
                :disabled="alertsState === 'saving'"
                @update:model-value="value => toggleAlert(event, value)"
              />
            </span>
          </div>
        </div>
        <p
          class="px-1 mt-1.5 mb-0 text-[11px] leading-snug"
          :class="
            alertsState === 'error' ? 'text-n-ruby-11' : 'text-n-slate-10'
          "
        >
          <template v-if="alertsState === 'loading'">
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.LOADING') }}
          </template>
          <template v-else-if="alertsState === 'saving'">
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.SAVING') }}
          </template>
          <template v-else-if="alertsState === 'error'">
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.ERROR') }}
          </template>
          <template v-else-if="alertsState === 'saved'">
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.SAVED') }}
          </template>
          <template v-else-if="alerts?.can_manage">
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.WHO_MANAGES') }}
          </template>
          <template v-else>
            {{ t('INTERNAL_CHAT.AUTO_ALERTS.READ_ONLY') }}
          </template>
        </p>
      </div>

      <!-- Membros (com presença) -->
      <div v-if="conversation.isGroup" class="px-3 pb-4">
        <p
          class="mb-0 px-1 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
        >
          {{
            t('INTERNAL_CHAT.HEADER.PARTICIPANTS', { count: members.length })
          }}
        </p>
        <div
          v-if="members.length > MEMBER_SEARCH_MIN"
          class="relative px-1 mb-1.5"
        >
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-4 top-1/2 text-n-slate-10"
          />
          <input
            v-model="memberQuery"
            type="text"
            :placeholder="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
            :aria-label="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
            class="reset-base w-full h-9 pl-9 pr-3 text-sm border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
          />
        </div>
        <p
          v-if="!visibleMembers.length"
          class="px-3 py-4 mb-0 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.LIST.NO_PEOPLE_MATCH') }}
        </p>
        <div v-else class="overflow-hidden rounded-2xl bg-n-alpha-1">
          <div
            v-for="m in visibleMembers"
            :key="m.id"
            class="flex items-center gap-3 px-3 py-2 border-b last:border-b-0 border-n-weak"
          >
            <Avatar
              :name="m.name"
              :src="m.avatarSrc"
              :size="36"
              :status="m.status"
              rounded-full
            />
            <span class="flex-1 min-w-0">
              <span
                class="block text-sm truncate text-n-slate-12"
                :title="m.name"
              >
                {{ m.name }}
              </span>
              <span
                class="block text-[11px]"
                :class="m.online ? 'text-n-teal-11' : 'text-n-slate-10'"
              >
                {{ m.label }}
              </span>
            </span>
            <span
              v-if="m.isMe"
              class="text-[11px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ t('INTERNAL_CHAT.INFO.YOU') }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
