<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  active: { type: Boolean, default: false },
  currentUserId: { type: [Number, String], default: null },
});

defineEmits(['select']);

const { t } = useI18n();
const unread = computed(() => props.conversation.unreadCount > 0);
// Prévia diz quem escreveu: "Você:" nas minhas, primeiro nome em grupo.
const preview = computed(() => {
  const lm = props.conversation.lastMessage || {};
  if (!lm.preview) return t('INTERNAL_CHAT.LIST.NO_MESSAGES');
  if (lm.fromMe) return `${t('INTERNAL_CHAT.LIST.YOU')}: ${lm.preview}`;
  return lm.author ? `${lm.author}: ${lm.preview}` : lm.preview;
});

// Bolinha verde de presença só para quem está online (grupo: nenhuma).
const status = computed(() =>
  props.conversation.presence === 'online' ? 'online' : null
);

// Grupo ad-hoc: foto composta com dois participantes (como no iPhone).
const groupFaces = computed(() => {
  const c = props.conversation;
  if (!c.isGroup || c.isTeam) return [];
  return (c.members || [])
    .filter(m => m.id !== props.currentUserId)
    .slice(0, 2);
});
</script>

<template>
  <button
    type="button"
    class="relative flex items-center w-full gap-3 py-2.5 pl-4 pr-3 text-left transition-colors duration-150 rounded-2xl"
    :class="active ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
    :aria-current="active ? 'true' : undefined"
    @click="$emit('select', conversation.id)"
  >
    <!-- Ponto de "tem novidade" à esquerda, como no app Mensagens -->
    <span
      class="absolute -translate-y-1/2 rounded-full left-1 top-1/2 size-2 transition-opacity duration-200"
      :class="
        unread
          ? conversation.muted
            ? 'bg-n-slate-9 opacity-100'
            : 'bg-n-teal-9 opacity-100'
          : 'opacity-0'
      "
    />

    <span v-if="groupFaces.length === 2" class="relative flex-shrink-0 size-12">
      <Avatar
        :name="groupFaces[0].name || ''"
        :src="groupFaces[0].avatar_url || ''"
        :size="32"
        rounded-full
        class="absolute top-0 left-0"
      />
      <span
        class="absolute bottom-0 right-0 rounded-full ring-2 ring-n-solid-1"
      >
        <Avatar
          :name="groupFaces[1].name || ''"
          :src="groupFaces[1].avatar_url || ''"
          :size="32"
          rounded-full
        />
      </span>
    </span>
    <Avatar
      v-else
      :name="conversation.name"
      :src="conversation.avatarSrc || ''"
      :icon-name="conversation.iconName"
      :size="48"
      :status="status"
      rounded-full
      class="flex-shrink-0"
    />

    <span class="flex-1 min-w-0">
      <span class="flex items-baseline justify-between gap-2">
        <span class="flex items-center min-w-0 gap-1.5">
          <span
            class="text-[15px] truncate text-n-slate-12"
            :class="unread ? 'font-bold' : 'font-semibold'"
          >
            {{ conversation.name }}
          </span>
          <span
            v-if="conversation.isGroup"
            class="flex-shrink-0 px-1.5 py-px text-[10px] font-semibold rounded-md uppercase tracking-wide bg-n-alpha-2 text-n-slate-11"
          >
            {{
              conversation.isTeam
                ? t('INTERNAL_CHAT.LIST.TEAM_BADGE')
                : t('INTERNAL_CHAT.LIST.GROUP_BADGE')
            }}
          </span>
          <span
            v-if="conversation.favorited"
            v-tooltip="t('INTERNAL_CHAT.LIST.FAVORITES')"
            class="flex-shrink-0 text-xs i-lucide-star text-n-amber-10"
          />
          <span
            v-if="conversation.muted"
            v-tooltip="t('INTERNAL_CHAT.MUTE.ACTIVE')"
            class="flex-shrink-0 text-xs i-lucide-bell-off text-n-slate-10"
          />
        </span>
        <span
          class="flex-shrink-0 text-xs tabular-nums"
          :class="
            unread && !conversation.muted
              ? 'text-n-teal-11 font-semibold'
              : 'text-n-slate-10'
          "
        >
          {{ conversation.time }}
        </span>
      </span>
      <span class="flex items-start justify-between gap-2 mt-0.5">
        <span
          class="flex-1 text-[13px] leading-snug line-clamp-2 break-words"
          :class="unread ? 'text-n-slate-12' : 'text-n-slate-11'"
        >
          {{ preview }}
        </span>
        <span
          v-if="unread"
          v-tooltip="
            t('INTERNAL_CHAT.LIST.UNREAD_COUNT', {
              count: conversation.unreadCount,
            })
          "
          class="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 mt-0.5 text-[11px] font-bold text-white rounded-full flex-shrink-0"
          :class="
            conversation.muted
              ? 'bg-n-slate-9'
              : 'bg-n-teal-10 dark:bg-n-teal-5'
          "
        >
          {{ conversation.unreadCount }}
        </span>
      </span>
    </span>
  </button>
</template>
