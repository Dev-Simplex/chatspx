<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useEscClose } from './useEscClose';
import { lastSeenText } from './lastSeen';

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
  'archive',
  'leave',
  'clear',
]);

const { t } = useI18n();
const showMenu = ref(false);
useEscClose(showMenu, () => {
  showMenu.value = false;
});

const online = computed(() => props.conversation.presence === 'online');
// Diz com quem se fala: presença do colega (DM) ou tipo + participantes + online.
const onlineCount = computed(
  () =>
    (props.conversation.members || []).filter(m => m.presence === 'online')
      .length
);
const statusText = computed(() => {
  const count = props.conversation.members?.length || 0;
  const params = { count, online: onlineCount.value };
  if (props.conversation.isTeam) {
    return t('INTERNAL_CHAT.HEADER.TEAM_MEMBERS_ONLINE', params);
  }
  if (props.conversation.isGroup) {
    return t('INTERNAL_CHAT.HEADER.MEMBERS_ONLINE', params);
  }
  const presence = props.conversation.presence || 'offline';
  if (presence === 'offline')
    return lastSeenText(t, props.conversation.lastSeenAt);
  return t(`INTERNAL_CHAT.PRESENCE.${presence.toUpperCase()}`);
});
// Só dá para "sair" de grupos ad-hoc; grupos de time são dirigidos pela equipe.
const canLeave = computed(
  () =>
    props.conversation.isGroup &&
    !props.conversation.isTeam &&
    !props.conversation.readOnly
);

// Fecha o menu; o item emite o próprio evento logo em seguida.
// Fecha o menu e devolve o foco ao ⋮: a janela que o item abrir volta para ele ao fechar.
const moreButton = ref(null);
const pick = () => {
  showMenu.value = false;
  moreButton.value?.focus();
};
</script>

<template>
  <!-- Cabeçalho centrado (como no iPhone): quem é + como está; ações à direita -->
  <header
    class="relative z-20 grid items-center flex-shrink-0 h-16 grid-cols-[1fr_auto_1fr] gap-2 px-3 border-b md:px-4 border-n-weak bg-n-background"
  >
    <div class="flex items-center min-w-0">
      <button
        v-tooltip="t('INTERNAL_CHAT.BACK')"
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 rounded-full size-9 md:hidden text-n-teal-11 hover:bg-n-alpha-2"
        :aria-label="t('INTERNAL_CHAT.BACK')"
        @click="emit('back')"
      >
        <span class="text-xl i-lucide-chevron-left" />
      </button>
    </div>

    <!-- Clicar em quem/qual grupo abre os detalhes (participantes, mídia) -->
    <button
      v-tooltip.bottom="t('INTERNAL_CHAT.HEADER.DETAILS')"
      type="button"
      class="flex items-center min-w-0 gap-2.5 px-3 py-1 transition-colors rounded-2xl hover:bg-n-alpha-1 max-w-[min(28rem,50vw)]"
      :class="infoActive ? 'bg-n-alpha-1' : ''"
      @click="emit('toggleInfo')"
    >
      <Avatar
        :name="conversation.name"
        :src="conversation.avatarSrc || ''"
        :icon-name="conversation.iconName"
        :size="36"
        :status="online ? 'online' : null"
        rounded-full
        class="flex-shrink-0"
      />
      <span class="flex flex-col min-w-0 text-left">
        <span class="flex items-center gap-1 min-w-0">
          <span
            class="text-[15px] font-semibold leading-tight truncate text-n-slate-12"
          >
            {{ conversation.name }}
          </span>
          <span
            v-if="conversation.muted"
            v-tooltip="t('INTERNAL_CHAT.MUTE.ACTIVE')"
            class="flex-shrink-0 text-xs i-lucide-bell-off text-n-slate-10"
          />
          <span
            class="flex-shrink-0 text-xs i-lucide-chevron-right text-n-slate-9"
          />
        </span>
        <span
          v-if="conversation.typingText"
          class="text-xs italic font-medium leading-tight truncate mt-0.5 text-n-teal-11"
          aria-live="polite"
        >
          {{ conversation.typingText }}
        </span>
        <span
          v-else
          class="text-xs leading-tight truncate mt-0.5"
          :class="online ? 'text-n-teal-11 font-medium' : 'text-n-slate-11'"
        >
          {{ statusText }}
        </span>
      </span>
    </button>

    <div class="flex items-center justify-end gap-0.5 text-n-slate-11">
      <button
        v-tooltip="t('INTERNAL_CHAT.HEADER.SEARCH')"
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-full size-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="searchActive ? 'text-n-teal-11 bg-n-alpha-2' : ''"
        :aria-label="t('INTERNAL_CHAT.HEADER.SEARCH')"
        @click="emit('toggleSearch')"
      >
        <span class="text-lg i-lucide-search" />
      </button>
      <button
        v-tooltip="t('INTERNAL_CHAT.HEADER.DETAILS')"
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-full size-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="infoActive ? 'text-n-teal-11 bg-n-alpha-2' : ''"
        :aria-label="t('INTERNAL_CHAT.HEADER.DETAILS')"
        @click="emit('toggleInfo')"
      >
        <span class="text-lg i-lucide-info" />
      </button>

      <!-- Mais opções -->
      <div class="relative">
        <button
          ref="moreButton"
          v-tooltip="t('INTERNAL_CHAT.HEADER.MORE')"
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-full size-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showMenu ? 'text-n-teal-11 bg-n-alpha-2' : ''"
          :aria-label="t('INTERNAL_CHAT.HEADER.MORE')"
          @click="showMenu = !showMenu"
        >
          <span class="text-lg i-lucide-ellipsis-vertical" />
        </button>
        <template v-if="showMenu">
          <div class="fixed inset-0 z-10" @click="showMenu = false" />
          <div
            class="absolute right-0 z-20 p-1.5 mt-2 overflow-hidden border shadow-xl top-full w-72 rounded-2xl bg-n-solid-1 border-n-weak"
          >
            <button
              v-if="conversation.isGroup"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('showMembers');
              "
            >
              <span class="text-base i-lucide-users" />
              {{ t('INTERNAL_CHAT.HEADER.SHOW_MEMBERS') }}
            </button>
            <button
              v-if="canManage"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('manage');
              "
            >
              <span class="text-base i-lucide-settings-2" />
              {{ t('INTERNAL_CHAT.MANAGE.TITLE') }}
            </button>
            <button
              v-if="!conversation.readOnly"
              type="button"
              class="flex items-start w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('toggleMute');
              "
            >
              <span
                class="mt-0.5 text-base"
                :class="
                  conversation.muted ? 'i-lucide-bell' : 'i-lucide-bell-off'
                "
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
              class="flex items-center w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('favorite');
              "
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
              v-if="!conversation.readOnly"
              type="button"
              class="flex items-start w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('archive');
              "
            >
              <span
                class="mt-0.5 text-base"
                :class="
                  conversation.archived
                    ? 'i-lucide-archive-restore'
                    : 'i-lucide-archive'
                "
              />
              <span class="flex-1">
                {{
                  conversation.archived
                    ? t('INTERNAL_CHAT.ARCHIVE.OFF')
                    : t('INTERNAL_CHAT.ARCHIVE.ON')
                }}
                <span
                  v-if="!conversation.archived"
                  class="block text-[11px] text-n-slate-10"
                >
                  {{ t('INTERNAL_CHAT.ARCHIVE.HINT') }}
                </span>
              </span>
            </button>
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
              @click="
                pick();
                emit('clear');
              "
            >
              <span class="text-base i-lucide-eraser" />
              {{ t('INTERNAL_CHAT.HEADER.CLEAR') }}
            </button>
            <button
              v-if="canLeave"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2.5 text-sm text-left rounded-xl text-n-ruby-11 hover:bg-n-ruby-3"
              @click="
                pick();
                emit('leave');
              "
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
