<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
  media: { type: Array, default: () => [] },
  docs: { type: Array, default: () => [] },
  canManage: { type: Boolean, default: false },
});

defineEmits(['close', 'manage', 'search', 'toggleMute', 'favorite']);

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
  return labelFor(props.conversation.presence); // DM → presença do colega
});

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
        label: labelFor(presence),
        rank: RANK[presence] ?? 2,
      };
    })
    // quem está online primeiro; você por último
    .sort((a, b) => a.isMe - b.isMe || a.rank - b.rank)
);
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
        <span class="text-lg i-lucide-x" />
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

      <!-- Mídia e documentos da conversa -->
      <div class="px-3 pb-3">
        <p
          class="px-1 mb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.INFO.MEDIA') }}
        </p>

        <div v-if="media.length" class="grid grid-cols-3 gap-1.5 mb-3">
          <a
            v-for="a in media"
            :key="a.id"
            :href="a.url"
            target="_blank"
            rel="noopener noreferrer"
            :title="a.filename"
            class="overflow-hidden rounded-xl aspect-square bg-n-alpha-2"
          >
            <img
              :src="a.url"
              :alt="a.filename"
              class="object-cover w-full h-full"
            />
          </a>
        </div>

        <div v-if="docs.length" class="space-y-1">
          <a
            v-for="a in docs"
            :key="a.id"
            :href="a.url"
            target="_blank"
            rel="noopener noreferrer"
            download
            class="flex items-center gap-2.5 px-2 py-2 rounded-lg hover:bg-n-alpha-1"
          >
            <span class="text-lg i-lucide-file-text text-n-slate-10" />
            <span class="flex-1 text-sm truncate text-n-slate-12">
              {{ a.filename }}
            </span>
            <span class="i-lucide-download text-n-slate-10" />
          </a>
        </div>

        <p
          v-if="!media.length && !docs.length"
          class="mb-0 px-3 py-4 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.INFO.NO_MEDIA') }}
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
        <div class="overflow-hidden rounded-2xl bg-n-alpha-1">
          <div
            v-for="m in members"
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
              <span class="block text-sm truncate text-n-slate-12">
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
