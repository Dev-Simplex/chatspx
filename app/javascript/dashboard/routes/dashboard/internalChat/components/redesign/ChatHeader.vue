<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  searchActive: { type: Boolean, default: false },
  infoActive: { type: Boolean, default: false },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits([
  'back',
  'toggleSearch',
  'toggleInfo',
  'showMembers',
  'manage',
  'toggleMute',
  'favorite',
  'leave',
  'clear',
]);

const { t } = useI18n();
const showMenu = ref(false);

const online = computed(() => props.conversation.presence === 'online');
// Diz com quem se fala: presença do colega (DM) ou tipo + nº de participantes.
const statusText = computed(() => {
  const count = props.conversation.members?.length || 0;
  if (props.conversation.isTeam) {
    return t('INTERNAL_CHAT.HEADER.TEAM_COUNT', { count });
  }
  if (props.conversation.isGroup) {
    return t('INTERNAL_CHAT.HEADER.GROUP_COUNT', { count });
  }
  const presence = props.conversation.presence || 'offline';
  return t(`INTERNAL_CHAT.PRESENCE.${presence.toUpperCase()}`);
});
// Só dá para "sair" de grupos ad-hoc; grupos de time são dirigidos pela equipe.
const canLeave = computed(
  () =>
    props.conversation.isGroup &&
    !props.conversation.isTeam &&
    !props.conversation.readOnly
);

const pick = event => {
  showMenu.value = false;
  emit(event);
};
</script>

<template>
  <header
    class="flex items-center flex-shrink-0 h-16 gap-3 px-4 border-b md:px-6 border-n-weak bg-n-background"
  >
    <button
      v-tooltip="t('INTERNAL_CHAT.BACK')"
      type="button"
      class="inline-flex items-center justify-center flex-shrink-0 -ml-1 rounded-lg w-9 h-9 md:hidden text-n-slate-11 hover:bg-n-alpha-2"
      :aria-label="t('INTERNAL_CHAT.BACK')"
      @click="emit('back')"
    >
      <span class="text-lg i-lucide-arrow-left" />
    </button>

    <!-- Clicar em quem/qual grupo abre os detalhes (participantes, mídia) -->
    <button
      v-tooltip="t('INTERNAL_CHAT.HEADER.DETAILS')"
      type="button"
      class="flex items-center flex-1 min-w-0 gap-3 text-left"
      @click="emit('toggleInfo')"
    >
      <Avatar
        :name="conversation.name"
        :src="conversation.avatarSrc || ''"
        :icon-name="conversation.iconName"
        :size="40"
        :status="online ? 'online' : null"
        rounded-full
      />
      <span class="flex-1 min-w-0">
        <span class="flex items-center gap-1.5">
          <span
            class="text-sm font-semibold leading-tight truncate text-n-slate-12"
          >
            {{ conversation.name }}
          </span>
          <span
            v-if="conversation.muted"
            v-tooltip="t('INTERNAL_CHAT.MUTE.ACTIVE')"
            class="flex-shrink-0 i-lucide-bell-off text-n-slate-10"
          />
        </span>
        <span
          class="block text-xs leading-tight mt-0.5"
          :class="online ? 'text-n-brand' : 'text-n-slate-11'"
        >
          {{ statusText }}
        </span>
      </span>
    </button>

    <div class="flex items-center gap-0.5 text-n-slate-11">
      <button
        v-tooltip="t('INTERNAL_CHAT.HEADER.SEARCH')"
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="searchActive ? 'text-n-brand bg-n-alpha-2' : ''"
        :aria-label="t('INTERNAL_CHAT.HEADER.SEARCH')"
        @click="emit('toggleSearch')"
      >
        <span class="text-lg i-lucide-search" />
      </button>
      <button
        v-tooltip="t('INTERNAL_CHAT.HEADER.DETAILS')"
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="infoActive ? 'text-n-brand bg-n-alpha-2' : ''"
        :aria-label="t('INTERNAL_CHAT.HEADER.DETAILS')"
        @click="emit('toggleInfo')"
      >
        <span class="text-lg i-lucide-info" />
      </button>

      <!-- Mais opções -->
      <div class="relative">
        <button
          v-tooltip="t('INTERNAL_CHAT.HEADER.MORE')"
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showMenu ? 'text-n-brand bg-n-alpha-2' : ''"
          :aria-label="t('INTERNAL_CHAT.HEADER.MORE')"
          @click="showMenu = !showMenu"
        >
          <span class="text-lg i-lucide-ellipsis-vertical" />
        </button>
        <template v-if="showMenu">
          <div class="fixed inset-0 z-10" @click="showMenu = false" />
          <div
            class="absolute right-0 z-20 py-1 mt-1 overflow-hidden border shadow-lg top-full w-64 rounded-xl bg-n-solid-1 border-n-weak"
          >
            <button
              v-if="conversation.isGroup"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="pick('showMembers')"
            >
              <span class="text-base i-lucide-users" />
              {{ t('INTERNAL_CHAT.HEADER.SHOW_MEMBERS') }}
            </button>
            <button
              v-if="canManage"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="pick('manage')"
            >
              <span class="text-base i-lucide-settings-2" />
              {{ t('INTERNAL_CHAT.MANAGE.TITLE') }}
            </button>
            <button
              v-if="!conversation.readOnly"
              type="button"
              class="flex items-start w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="pick('toggleMute')"
            >
              <span
                class="mt-0.5 text-base"
                :class="conversation.muted ? 'i-lucide-bell' : 'i-lucide-bell-off'"
              />
              <span class="flex-1">
                {{
                  conversation.muted
                    ? t('INTERNAL_CHAT.MUTE.OFF')
                    : t('INTERNAL_CHAT.MUTE.ON')
                }}
                <span
                  v-if="!conversation.muted"
                  class="block text-[11px] text-n-slate-10"
                >
                  {{ t('INTERNAL_CHAT.MUTE.HINT') }}
                </span>
              </span>
            </button>
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="pick('favorite')"
            >
              <span
                class="text-base"
                :class="
                  conversation.favorited ? 'i-lucide-star-off' : 'i-lucide-star'
                "
              />
              {{
                conversation.favorited
                  ? t('INTERNAL_CHAT.HEADER.UNFAVORITE')
                  : t('INTERNAL_CHAT.HEADER.FAVORITE')
              }}
            </button>
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="pick('clear')"
            >
              <span class="text-base i-lucide-eraser" />
              {{ t('INTERNAL_CHAT.HEADER.CLEAR') }}
            </button>
            <button
              v-if="canLeave"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-ruby-11 hover:bg-n-ruby-3"
              @click="pick('leave')"
            >
              <span class="text-base i-lucide-log-out" />
              {{ t('INTERNAL_CHAT.MANAGE.LEAVE') }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </header>
</template>
