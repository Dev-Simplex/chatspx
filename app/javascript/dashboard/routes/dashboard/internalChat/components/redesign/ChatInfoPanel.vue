<script setup>
import { ref, computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { currentUser, availableContacts } from './mockData.js';

const props = defineProps({
  conversation: { type: Object, required: true },
});

defineEmits(['close']);

const view = ref('home'); // 'home' | 'media' | 'notifications' | 'members'

const online = computed(() => props.conversation.presence === 'online');

const SECTIONS = [
  { key: 'media', icon: 'i-lucide-image', label: 'Mídia, links e docs' },
  { key: 'notifications', icon: 'i-lucide-bell', label: 'Notificações' },
  { key: 'members', icon: 'i-lucide-users', label: 'Membros' },
];

// Mock members: DM = eu + a pessoa; grupo = eu + alguns contatos.
const members = computed(() => {
  const me = { id: currentUser.id, name: currentUser.name, role: 'você' };
  if (!props.conversation.isGroup) {
    return [{ id: 'other', name: props.conversation.name, role: null }, me];
  }
  return [
    { id: 'admin', name: props.conversation.name, role: 'admin' },
    me,
    ...availableContacts.slice(0, 3).map(c => ({ ...c, role: null })),
  ];
});

// Mock notificações (toggles funcionais no protótipo).
const muted = ref(false);
const sound = ref(true);
const desktop = ref(true);
const NOTIF = computed(() => [
  { key: 'muted', label: 'Silenciar conversa', model: muted },
  { key: 'sound', label: 'Som ao receber', model: sound },
  { key: 'desktop', label: 'Notificação no desktop', model: desktop },
]);

const titleByView = {
  home: 'Informações',
  media: 'Mídia, links e docs',
  notifications: 'Notificações',
  members: 'Membros',
};
</script>

<template>
  <!-- Protótipo visual (dados fictícios); i18n entra na versão final. -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex flex-col h-full bg-n-solid-1">
    <header
      class="flex items-center flex-shrink-0 h-16 gap-2 px-3 border-b border-n-weak"
    >
      <button
        v-if="view !== 'home'"
        type="button"
        class="inline-flex items-center justify-center rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2"
        title="Voltar"
        @click="view = 'home'"
      >
        <span class="text-lg i-lucide-arrow-left" />
      </button>
      <h3 class="flex-1 text-sm font-semibold text-n-slate-12">
        {{ titleByView[view] }}
      </h3>
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-lg w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2"
        title="Fechar"
        @click="$emit('close')"
      >
        <span class="text-lg i-lucide-x" />
      </button>
    </header>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <!-- Home -->
      <template v-if="view === 'home'">
        <div
          class="flex flex-col items-center gap-2 px-4 py-6 border-b border-n-weak"
        >
          <Avatar
            :name="conversation.name"
            :src="conversation.avatarSrc || ''"
            :icon-name="conversation.iconName"
            :size="80"
            :status="online ? 'online' : null"
            rounded-full
          />
          <h2 class="text-base font-semibold text-center text-n-slate-12">
            {{ conversation.name }}
          </h2>
          <p
            class="text-xs"
            :class="online ? 'text-n-brand' : 'text-n-slate-10'"
          >
            {{ conversation.isGroup ? 'Grupo' : online ? 'Online' : 'Offline' }}
          </p>
        </div>
        <div class="p-2">
          <button
            v-for="s in SECTIONS"
            :key="s.key"
            type="button"
            class="flex items-center justify-between w-full gap-3 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
            @click="view = s.key"
          >
            <span class="flex items-center gap-3">
              <span class="text-lg text-n-slate-10" :class="s.icon" />
              {{ s.label }}
            </span>
            <span class="i-lucide-chevron-right text-n-slate-10" />
          </button>
        </div>
      </template>

      <!-- Mídia -->
      <template v-else-if="view === 'media'">
        <div class="p-4">
          <p class="mb-2 text-xs font-semibold uppercase text-n-slate-10">
            Mídia
          </p>
          <div class="grid grid-cols-3 gap-1.5 mb-4">
            <div
              v-for="n in 6"
              :key="n"
              class="rounded-lg aspect-square bg-n-alpha-2 flex items-center justify-center text-n-slate-9"
            >
              <span class="text-xl i-lucide-image" />
            </div>
          </div>
          <p class="mb-2 text-xs font-semibold uppercase text-n-slate-10">
            Documentos
          </p>
          <div class="space-y-1">
            <div
              v-for="doc in ['Relatório de vendas.pdf', 'Planilha Q2.xlsx']"
              :key="doc"
              class="flex items-center gap-2.5 px-2 py-2 rounded-lg hover:bg-n-alpha-1"
            >
              <span class="text-lg i-lucide-file-text text-n-slate-10" />
              <span class="text-sm truncate text-n-slate-12">{{ doc }}</span>
            </div>
          </div>
        </div>
      </template>

      <!-- Notificações -->
      <template v-else-if="view === 'notifications'">
        <div class="p-2">
          <button
            v-for="n in NOTIF"
            :key="n.key"
            type="button"
            role="switch"
            :aria-checked="n.model.value"
            class="flex items-center justify-between w-full gap-3 px-3 py-3 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
            @click="n.model.value = !n.model.value"
          >
            {{ n.label }}
            <span
              class="relative inline-flex items-center flex-shrink-0 h-5 transition-colors rounded-full w-9"
              :class="n.model.value ? 'bg-n-brand' : 'bg-n-slate-4'"
            >
              <span
                class="inline-block w-4 h-4 transition-transform bg-white rounded-full shadow"
                :class="n.model.value ? 'translate-x-4' : 'translate-x-0.5'"
              />
            </span>
          </button>
        </div>
      </template>

      <!-- Membros -->
      <template v-else-if="view === 'members'">
        <div class="p-2">
          <div
            v-for="m in members"
            :key="m.id"
            class="flex items-center gap-3 px-3 py-2 rounded-xl hover:bg-n-alpha-1"
          >
            <Avatar :name="m.name" :size="36" rounded-full />
            <span class="flex-1 text-sm truncate text-n-slate-12">
              {{ m.name }}
            </span>
            <span
              v-if="m.role"
              class="text-[11px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{ m.role }}
            </span>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
