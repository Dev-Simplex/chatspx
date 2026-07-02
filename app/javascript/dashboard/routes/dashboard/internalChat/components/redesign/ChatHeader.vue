<script setup>
import { ref, computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  searchActive: { type: Boolean, default: false },
  infoActive: { type: Boolean, default: false },
});

const emit = defineEmits([
  'back',
  'toggleSearch',
  'toggleInfo',
  'favorite',
  'markUnread',
  'clear',
]);

const showMenu = ref(false);

const online = computed(() => props.conversation.presence === 'online');
const statusText = computed(() => {
  if (props.conversation.isGroup) return 'Grupo';
  return online.value ? 'Online' : 'Offline';
});

const emitFavorite = () => {
  showMenu.value = false;
  emit('favorite');
};
const emitMarkUnread = () => {
  showMenu.value = false;
  emit('markUnread');
};
const emitClear = () => {
  showMenu.value = false;
  emit('clear');
};
</script>

<template>
  <!-- Protótipo visual (dados fictícios); i18n entra na versão final. -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <header
    class="flex items-center flex-shrink-0 h-16 gap-3 px-4 border-b md:px-6 border-n-weak bg-n-background"
  >
    <button
      type="button"
      class="inline-flex items-center justify-center flex-shrink-0 -ml-1 rounded-lg w-9 h-9 md:hidden text-n-slate-11 hover:bg-n-alpha-2"
      title="Voltar"
      @click="$emit('back')"
    >
      <span class="text-lg i-lucide-arrow-left" />
    </button>

    <Avatar
      :name="conversation.name"
      :src="conversation.avatarSrc || ''"
      :icon-name="conversation.iconName"
      :size="40"
      :status="online ? 'online' : null"
      rounded-full
    />
    <div class="flex-1 min-w-0">
      <h2 class="text-sm font-semibold leading-tight truncate text-n-slate-12">
        {{ conversation.name }}
      </h2>
      <p
        class="text-xs leading-tight mt-0.5"
        :class="online ? 'text-n-brand' : 'text-n-slate-10'"
      >
        {{ statusText }}
      </p>
    </div>

    <div class="flex items-center gap-0.5 text-n-slate-11">
      <button
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="searchActive ? 'text-n-brand bg-n-alpha-2' : ''"
        title="Pesquisar"
        @click="$emit('toggleSearch')"
      >
        <span class="text-lg i-lucide-search" />
      </button>
      <button
        type="button"
        class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="infoActive ? 'text-n-brand bg-n-alpha-2' : ''"
        title="Informações"
        @click="$emit('toggleInfo')"
      >
        <span class="text-lg i-lucide-info" />
      </button>

      <!-- More options -->
      <div class="relative">
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-lg w-9 h-9 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showMenu ? 'text-n-brand bg-n-alpha-2' : ''"
          title="Mais opções"
          @click="showMenu = !showMenu"
        >
          <span class="text-lg i-lucide-ellipsis-vertical" />
        </button>
        <template v-if="showMenu">
          <div class="fixed inset-0 z-10" @click="showMenu = false" />
          <div
            class="absolute right-0 z-20 py-1 mt-1 overflow-hidden border shadow-lg top-full w-52 rounded-xl bg-n-solid-1 border-n-weak"
          >
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="emitFavorite"
            >
              <span
                class="text-base"
                :class="
                  conversation.favorited ? 'i-lucide-star-off' : 'i-lucide-star'
                "
              />
              {{
                conversation.favorited
                  ? 'Remover dos favoritos'
                  : 'Favoritar conversa'
              }}
            </button>
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="emitMarkUnread"
            >
              <span class="text-base i-lucide-mail" />
              Marcar como não lida
            </button>
            <button
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-sm text-left text-n-ruby-11 hover:bg-n-ruby-3"
              @click="emitClear"
            >
              <span class="text-base i-lucide-trash-2" />
              Limpar conversa
            </button>
          </div>
        </template>
      </div>
    </div>
  </header>
</template>
