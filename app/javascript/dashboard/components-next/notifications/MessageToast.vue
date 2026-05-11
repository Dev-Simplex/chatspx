<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { emitter } from 'shared/helpers/mitt';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'next/avatar/Avatar.vue';

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const toasts = ref([]);
let nextId = 1;
const TOAST_DURATION = 6000;

const dismiss = id => {
  const idx = toasts.value.findIndex(t => t.id === id);
  if (idx >= 0) toasts.value.splice(idx, 1);
};

const open = toast => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: toast.conversationId,
    },
  });
  dismiss(toast.id);
};

const showToast = payload => {
  const id = nextId;
  nextId += 1;
  // Dedupe: se já tem toast pra mesma conversa, atualiza em vez de adicionar
  const existing = toasts.value.find(
    t => t.conversationId === payload.conversationId
  );
  if (existing) {
    existing.contactName = payload.contactName;
    existing.contactAvatar = payload.contactAvatar;
    existing.messagePreview = payload.messagePreview;
    clearTimeout(existing.timer);
    existing.timer = setTimeout(() => dismiss(existing.id), TOAST_DURATION);
    return;
  }
  const toast = {
    id,
    conversationId: payload.conversationId,
    contactName: payload.contactName || 'Nova mensagem',
    contactAvatar: payload.contactAvatar,
    messagePreview: payload.messagePreview,
    timer: null,
  };
  toast.timer = setTimeout(() => dismiss(id), TOAST_DURATION);
  toasts.value.push(toast);
  // Cap em 3 toasts simultâneos — descarta o mais antigo
  if (toasts.value.length > 3) {
    const oldest = toasts.value.shift();
    clearTimeout(oldest.timer);
  }
};

onMounted(() => {
  emitter.on('newMessageToast', showToast);
});

onBeforeUnmount(() => {
  emitter.off('newMessageToast', showToast);
  toasts.value.forEach(t => clearTimeout(t.timer));
});
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed bottom-4 ltr:right-4 rtl:left-4 z-[10000] flex flex-col gap-2 pointer-events-none"
    >
      <TransitionGroup
        enter-active-class="transition duration-200 ease-out"
        enter-from-class="opacity-0 translate-y-4"
        enter-to-class="opacity-100 translate-y-0"
        leave-active-class="transition duration-150 ease-in"
        leave-from-class="opacity-100"
        leave-to-class="opacity-0 translate-x-4"
      >
        <button
          v-for="toast in toasts"
          :key="toast.id"
          type="button"
          class="pointer-events-auto flex items-center gap-3 w-80 px-3 py-2.5 rounded-xl bg-n-solid-1 dark:bg-[#202c33] border border-n-weak shadow-[0_8px_24px_rgba(0,0,0,0.18)] hover:bg-n-alpha-2 transition-colors text-left rtl:text-right cursor-pointer"
          @click="open(toast)"
        >
          <Avatar
            :name="toast.contactName"
            :src="toast.contactAvatar"
            :size="40"
            class="flex-shrink-0"
          />
          <div class="flex-1 min-w-0">
            <div class="text-sm font-semibold text-n-slate-12 truncate">
              {{ toast.contactName }}
            </div>
            <div class="text-xs text-n-slate-11 truncate">
              {{ toast.messagePreview }}
            </div>
          </div>
          <span
            class="i-lucide-message-circle text-[#2dc46f] size-5 flex-shrink-0"
            aria-hidden="true"
          />
        </button>
      </TransitionGroup>
    </div>
  </Teleport>
</template>
