<script setup>
import { onBeforeUnmount, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import SenderAvatar from './SenderAvatar.vue';
import { formatDateTime } from '../composables/useGroupedByDate.js';

const props = defineProps({
  item: { type: Object, required: true },
});
const emit = defineEmits(['close', 'openConversation']);

const { t } = useI18n();

const onKey = e => {
  if (e.key === 'Escape') emit('close');
};

onMounted(() => {
  window.addEventListener('keydown', onKey);
  document.body.style.overflow = 'hidden';
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey);
  document.body.style.overflow = '';
});
</script>

<template>
  <div
    class="fixed inset-0 z-[1000] bg-n-black/90 flex flex-col backdrop-blur-md"
    @click.self="emit('close')"
  >
    <header
      class="flex items-center justify-between px-5 py-3 text-white border-b border-white/10"
    >
      <div class="flex items-center gap-3 min-w-0 flex-1">
        <SenderAvatar :sender="props.item.sender" :size="36" />
        <div class="flex flex-col min-w-0">
          <span class="font-semibold text-sm truncate">
            {{ props.item.sender?.name || t('GALLERY.UNKNOWN_SENDER') }}
          </span>
          <span class="text-xs text-white/70 tabular-nums">
            {{ formatDateTime(props.item.createdAt) }}
            <template v-if="props.item.filename">
              <span aria-hidden="true">&middot;</span> {{ props.item.filename }}
            </template>
          </span>
        </div>
      </div>
      <div class="flex items-center gap-1">
        <a
          v-if="props.item.dataUrl"
          :href="props.item.dataUrl"
          :download="props.item.filename"
          target="_blank"
          rel="noopener noreferrer"
          class="size-10 rounded-xl hover:bg-white/10 flex items-center justify-center transition-colors"
          :title="t('GALLERY.ACTIONS.DOWNLOAD')"
        >
          <span class="i-lucide-download size-5" />
        </a>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 h-10 px-3 rounded-xl hover:bg-white/10 text-sm font-medium transition-colors"
          :title="t('GALLERY.ACTIONS.OPEN_CONVERSATION')"
          @click="emit('openConversation', props.item)"
        >
          <span class="i-lucide-message-circle size-4" />
          <span class="hidden sm:inline">{{
            t('GALLERY.ACTIONS.OPEN_CONVERSATION')
          }}</span>
        </button>
        <button
          type="button"
          class="size-10 rounded-xl hover:bg-white/10 flex items-center justify-center transition-colors"
          :title="t('GALLERY.ACTIONS.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>
    </header>
    <main
      class="flex-1 flex items-center justify-center min-h-0 p-6"
      @click.self="emit('close')"
    >
      <video
        v-if="props.item.fileType === 'video'"
        :src="props.item.dataUrl"
        controls
        autoplay
        class="max-h-full max-w-full rounded-lg shadow-2xl"
      />
      <img
        v-else
        :src="props.item.dataUrl"
        :alt="props.item.filename || ''"
        class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
      />
    </main>
  </div>
</template>
