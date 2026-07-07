<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
  media: { type: Array, default: () => [] },
  docs: { type: Array, default: () => [] },
});

defineEmits(['close']);

const STATUS_LABEL = { online: 'online', busy: 'ocupado', offline: 'offline' };
const labelFor = presence => STATUS_LABEL[presence] || 'offline';

const online = computed(() => props.conversation.presence === 'online');
const headerStatus = computed(() => {
  if (props.conversation.isTeam) return 'Grupo de time';
  if (props.conversation.isGroup) return 'Grupo';
  return labelFor(props.conversation.presence); // DM → presença do colega
});

const members = computed(() =>
  (props.conversation.members || []).map(m => {
    const presence = m.presence || 'offline';
    return {
      id: m.id,
      name: m.name,
      avatarSrc: m.avatar_url || '',
      isMe: m.id === props.currentUserId,
      status: presence, // dot no Avatar
      online: presence === 'online',
      label: labelFor(presence),
    };
  })
);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="flex flex-col h-full bg-n-solid-1">
    <header
      class="flex items-center flex-shrink-0 h-16 gap-2 px-3 border-b border-n-weak"
    >
      <h3 class="flex-1 text-sm font-semibold text-n-slate-12">Informações</h3>
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
      <!-- Cabeçalho: avatar + nome + tipo/presença -->
      <div
        class="flex flex-col items-center gap-2 px-4 py-6 border-b border-n-weak"
      >
        <Avatar
          :name="conversation.name"
          :src="conversation.avatarSrc || ''"
          :icon-name="conversation.iconName"
          :size="80"
          :status="conversation.isGroup ? null : conversation.presence"
          rounded-full
        />
        <h2 class="text-base font-semibold text-center text-n-slate-12">
          {{ conversation.name }}
        </h2>
        <p class="text-xs" :class="online ? 'text-n-brand' : 'text-n-slate-10'">
          {{ headerStatus }}
        </p>
      </div>

      <!-- Mídia e documentos da conversa -->
      <div class="p-3 border-b border-n-weak">
        <p
          class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
        >
          Mídia e documentos
        </p>

        <div v-if="media.length" class="grid grid-cols-3 gap-1.5 mb-3">
          <a
            v-for="a in media"
            :key="a.id"
            :href="a.url"
            target="_blank"
            rel="noopener noreferrer"
            :title="a.filename"
            class="overflow-hidden rounded-lg aspect-square bg-n-alpha-2"
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
          class="py-4 text-xs text-center text-n-slate-10"
        >
          Nenhuma mídia ou documento nesta conversa ainda.
        </p>
      </div>

      <!-- Membros (com presença) -->
      <div v-if="conversation.isGroup" class="p-2">
        <p
          class="px-2 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ members.length }} membros
        </p>
        <div
          v-for="m in members"
          :key="m.id"
          class="flex items-center gap-3 px-3 py-2 rounded-xl hover:bg-n-alpha-1"
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
              :class="m.online ? 'text-n-brand' : 'text-n-slate-10'"
            >
              {{ m.label }}
            </span>
          </span>
          <span
            v-if="m.isMe"
            class="text-[11px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            você
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
