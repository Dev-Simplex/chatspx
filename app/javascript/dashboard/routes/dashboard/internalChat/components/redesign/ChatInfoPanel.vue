<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
});

defineEmits(['close']);

const online = computed(() => props.conversation.presence === 'online');

const typeLabel = computed(() => {
  if (props.conversation.isTeam) return 'Grupo de time';
  if (props.conversation.isGroup) return 'Grupo';
  return online.value ? 'Online' : 'Offline';
});

const members = computed(() =>
  (props.conversation.members || []).map(m => ({
    id: m.id,
    name: m.name,
    avatarSrc: m.avatar_url || '',
    isMe: m.id === props.currentUserId,
  }))
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
        <p class="text-xs" :class="online ? 'text-n-brand' : 'text-n-slate-10'">
          {{ typeLabel }}
        </p>
      </div>

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
          <Avatar :name="m.name" :src="m.avatarSrc" :size="36" rounded-full />
          <span class="flex-1 text-sm truncate text-n-slate-12">{{
            m.name
          }}</span>
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
