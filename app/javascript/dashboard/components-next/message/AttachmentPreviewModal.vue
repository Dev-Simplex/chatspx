<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import Icon from 'next/icon/Icon.vue';
import ProgressRing from 'dashboard/components-next/upload/ProgressRing.vue';
import WormLoader from 'dashboard/components-next/upload/WormLoader.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  show: { type: Boolean, default: false },
  files: { type: Array, default: () => [] },
  caption: { type: String, default: '' },
  sending: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:caption',
  'update:files',
  'send',
  'add-more',
  'close',
  'edit-image',
  'retry-upload',
]);

const { t } = useI18n();

// Per-attachment DirectUpload state (set while a file uploads on attach).
const uploadStatusOf = att => att?.uploadStatus;
const uploadProgressOf = att =>
  typeof att?.uploadProgress === 'number' ? att.uploadProgress : null;

const activeIndex = ref(0);
const captionLocal = ref(props.caption);

// Real upload percentage for the message-with-attachments POST, surfaced by
// MessageApi.create over the bus. null = indeterminate (length not computable
// or upload not started yet) → the ring spins instead of filling.
const uploadPercent = ref(null);

const onUploadProgress = ({ percent } = {}) => {
  uploadPercent.value = percent ?? null;
};

const active = computed(() => props.files[activeIndex.value] || null);

const getType = att => {
  if (!att) return '';
  const resource = att.resource || att;
  return resource.content_type || resource.type || '';
};

const isImage = att => getType(att).includes('image');
const isVideo = att => getType(att).includes('video');
const isAudio = att => getType(att).includes('audio');
const isPdf = att => getType(att).includes('pdf');

const fileName = att => {
  if (!att) return '';
  const resource = att.resource || att;
  return resource.name || resource.filename || att.name || '';
};

const fileSize = att => {
  if (!att) return '';
  const resource = att.resource || att;
  const size = resource.size || att.size || 0;
  if (!size) return '';
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
};

const sortedFiles = computed({
  get: () => props.files,
  set: value => emit('update:files', value),
});

const setActive = index => {
  activeIndex.value = index;
};

const removeAt = index => {
  const next = props.files.filter((_, i) => i !== index);
  emit('update:files', next);
  if (activeIndex.value >= next.length) {
    activeIndex.value = Math.max(0, next.length - 1);
  }
};

const onSend = () => {
  // Não bloqueia em uploads pendentes: o ReplyBox "arma" o envio e dispara
  // sozinho quando o upload termina (a atendente segue conversando).
  if (props.sending) return;
  emit('send');
};

const onRetry = att => {
  // eslint-disable-next-line vue/custom-event-name-casing
  emit('retry-upload', att);
};

const onClose = () => emit('close');

const onEdit = action => {
  if (!active.value || !isImage(active.value)) return;
  // eslint-disable-next-line vue/custom-event-name-casing
  emit('edit-image', { file: active.value, action });
};

const onKeyDown = event => {
  if (event.key === 'Escape' && props.show) {
    onClose();
  }
};

watch(captionLocal, value => {
  emit('update:caption', value);
});

watch(
  () => props.caption,
  value => {
    if (value !== captionLocal.value) {
      captionLocal.value = value;
    }
  }
);

watch(
  () => props.show,
  value => {
    if (value) {
      activeIndex.value = 0;
    }
  }
);

// Reset the ring each time a send starts so a previous run's % never lingers.
watch(
  () => props.sending,
  value => {
    if (value) uploadPercent.value = null;
  }
);

watch(
  () => props.files.length,
  length => {
    if (props.show && length === 0) {
      emit('close');
    }
  }
);

onMounted(() => {
  window.addEventListener('keydown', onKeyDown);
  emitter.on(BUS_EVENTS.MESSAGE_UPLOAD_PROGRESS, onUploadProgress);
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeyDown);
  emitter.off(BUS_EVENTS.MESSAGE_UPLOAD_PROGRESS, onUploadProgress);
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 scale-95"
      enter-to-class="opacity-100 scale-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-95"
    >
      <div
        v-if="show"
        role="dialog"
        aria-modal="true"
        :aria-label="t('ATTACHMENT_PREVIEW.CLOSE')"
        class="fixed inset-0 z-[9100] flex flex-col bg-wa-pane-light dark:bg-wa-pane-dark"
      >
        <header
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak h-[60px]"
        >
          <button
            type="button"
            :aria-label="t('ATTACHMENT_PREVIEW.CLOSE')"
            class="grid place-content-center size-8 rounded-full hover:bg-n-alpha-2 text-n-slate-12"
            @click="onClose"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
          <div class="flex-1" />
          <div class="w-8" />
        </header>

        <div class="flex-1 flex items-center justify-center relative px-6 py-4">
          <!--
            Sending overlay: while the message+attachments POST is in flight we
            dim the preview and show the upload ring (real % when the length is
            computable, otherwise an indeterminate spin). The disabled send
            button + dim already convey "sending", so this is supplementary.
          -->
          <Transition
            enter-active-class="transition-opacity duration-200 ease-out"
            enter-from-class="opacity-0"
            leave-active-class="transition-opacity duration-150 ease-in"
            leave-to-class="opacity-0"
          >
            <!--
              Two overlays share this spot:
              - while the ACTIVE attachment is still uploading (DirectUpload on
                attach), show its real per-file progress ring;
              - while the message POST is in flight (`sending`), show the send
                ring. They never co-occur (Send is gated on uploads finishing).
            -->
            <div
              v-if="uploadStatusOf(active) === 'uploading'"
              class="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 bg-n-black/65 backdrop-blur-md"
            >
              <WormLoader :size="96" />
              <span
                v-if="uploadProgressOf(active) !== null"
                class="text-base font-semibold text-white tabular-nums"
              >
                {{ `${uploadProgressOf(active)}%` }}
              </span>
              <span class="text-sm text-white/90">
                {{ t('ATTACHMENT_PREVIEW.UPLOADING') }}
              </span>
            </div>
            <div
              v-else-if="uploadStatusOf(active) === 'failed'"
              class="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 bg-n-black/70 backdrop-blur-md"
            >
              <Icon
                icon="i-lucide-alert-triangle"
                class="size-10 text-n-ruby-9"
              />
              <button
                type="button"
                class="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-white/90 text-sm text-n-slate-12 hover:bg-white"
                @click="onRetry(active)"
              >
                <Icon icon="i-lucide-rotate-cw" class="size-4" />
                {{ t('ATTACHMENT_PREVIEW.RETRY') }}
              </button>
            </div>
            <div
              v-else-if="sending"
              class="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 bg-n-black/65 backdrop-blur-md"
            >
              <WormLoader :size="96" />
              <span
                v-if="uploadPercent !== null"
                class="text-base font-semibold text-white tabular-nums"
              >
                {{ `${uploadPercent}%` }}
              </span>
            </div>
          </Transition>
          <div
            v-if="active"
            class="flex items-center justify-center w-full h-full relative"
          >
            <img
              v-if="isImage(active)"
              :src="active.thumb"
              :alt="fileName(active)"
              class="max-h-[70vh] max-w-full object-contain"
            />
            <video
              v-else-if="isVideo(active)"
              :src="active.thumb"
              controls
              playsinline
              class="max-h-[70vh] max-w-full object-contain"
            />
            <div
              v-else-if="isAudio(active)"
              class="flex flex-col items-center gap-4 p-8 rounded-lg bg-wa-surface-light dark:bg-wa-surface-dark min-w-[320px]"
            >
              <Icon icon="i-lucide-music" class="size-16 text-wa-teal" />
              <span class="text-sm text-n-slate-12 truncate max-w-[280px]">
                {{ fileName(active) }}
              </span>
              <audio :src="active.thumb" controls class="w-full" />
            </div>
            <div
              v-else
              class="flex flex-col items-center gap-3 p-10 rounded-lg bg-wa-surface-light dark:bg-wa-surface-dark min-w-[360px]"
            >
              <Icon
                :icon="isPdf(active) ? 'i-lucide-file-text' : 'i-lucide-file'"
                class="size-20 text-wa-teal"
              />
              <span class="text-base text-n-slate-12 truncate max-w-[320px]">
                {{ fileName(active) }}
              </span>
              <span v-if="fileSize(active)" class="text-xs text-wa-text-muted">
                {{ fileSize(active) }}
              </span>
            </div>

            <span
              v-if="files.length > 1"
              class="absolute bottom-2 left-4 text-xs text-wa-text-muted"
            >
              {{
                t('ATTACHMENT_PREVIEW.COUNTER', {
                  current: activeIndex + 1,
                  total: files.length,
                })
              }}
            </span>
          </div>

          <div
            v-if="active && isImage(active)"
            class="absolute top-1/2 -translate-y-1/2 right-4 flex flex-col gap-4 px-2"
          >
            <button
              type="button"
              :aria-label="t('ATTACHMENT_PREVIEW.CROP')"
              class="grid place-content-center size-10 rounded-full bg-wa-surface-light dark:bg-wa-surface-dark hover:bg-n-alpha-2 text-n-slate-12"
              @click="onEdit('crop')"
            >
              <Icon icon="i-lucide-crop" class="size-5" />
            </button>
            <button
              type="button"
              :aria-label="t('ATTACHMENT_PREVIEW.DRAW')"
              class="grid place-content-center size-10 rounded-full bg-wa-surface-light dark:bg-wa-surface-dark hover:bg-n-alpha-2 text-n-slate-12"
              @click="onEdit('draw')"
            >
              <Icon icon="i-lucide-pencil" class="size-5" />
            </button>
            <button
              type="button"
              :aria-label="t('ATTACHMENT_PREVIEW.ADD_TEXT')"
              class="grid place-content-center size-10 rounded-full bg-wa-surface-light dark:bg-wa-surface-dark hover:bg-n-alpha-2 text-n-slate-12"
              @click="onEdit('text')"
            >
              <Icon icon="i-lucide-type" class="size-5" />
            </button>
          </div>
        </div>

        <div class="px-6 pb-3">
          <div
            class="mx-auto max-w-2/3 rounded-lg bg-wa-caption-bg-light dark:bg-wa-caption-bg-dark"
          >
            <input
              v-model="captionLocal"
              type="text"
              :placeholder="t('ATTACHMENT_PREVIEW.CAPTION_PLACEHOLDER')"
              class="w-full bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-wa-text-muted py-[9px] px-3"
            />
          </div>
        </div>

        <div
          class="flex items-center gap-3 px-3 py-3 bg-wa-surface-light dark:bg-wa-surface-dark relative"
        >
          <draggable
            v-model="sortedFiles"
            :item-key="item => item.id || item.thumb"
            class="flex items-center gap-2 overflow-x-auto flex-1"
            tag="div"
          >
            <template #item="{ element, index }">
              <div
                class="attachment-thumb relative shrink-0 size-14 rounded-md overflow-hidden cursor-pointer"
                :style="{ '--thumb-index': index }"
                :class="index === activeIndex ? 'ring-2 ring-wa-teal' : ''"
                @click="setActive(index)"
              >
                <img
                  v-if="isImage(element)"
                  :src="element.thumb"
                  :alt="fileName(element)"
                  class="size-full object-cover"
                />
                <video
                  v-else-if="isVideo(element)"
                  :src="element.thumb"
                  class="size-full object-cover"
                />
                <div
                  v-else
                  class="size-full grid place-content-center bg-n-alpha-2"
                >
                  <Icon
                    :icon="
                      isAudio(element)
                        ? 'i-lucide-music'
                        : isPdf(element)
                          ? 'i-lucide-file-text'
                          : 'i-lucide-file'
                    "
                    class="size-6 text-n-slate-11"
                  />
                </div>
                <!-- Per-attachment upload status badge -->
                <div
                  v-if="uploadStatusOf(element) === 'uploading'"
                  class="absolute inset-0 grid place-content-center bg-n-black/45"
                >
                  <ProgressRing
                    :value="uploadProgressOf(element)"
                    :size="28"
                    :stroke="3"
                  />
                </div>
                <div
                  v-else-if="uploadStatusOf(element) === 'uploaded'"
                  class="absolute bottom-0.5 left-0.5 grid place-content-center size-4 rounded-full bg-wa-teal text-white"
                >
                  <Icon icon="i-lucide-check" class="size-3" />
                </div>
                <button
                  v-else-if="uploadStatusOf(element) === 'failed'"
                  type="button"
                  :aria-label="t('ATTACHMENT_PREVIEW.RETRY')"
                  class="absolute inset-0 grid place-content-center bg-n-black/55 text-n-ruby-9"
                  @click.stop="onRetry(element)"
                >
                  <Icon icon="i-lucide-rotate-cw" class="size-5" />
                </button>
                <button
                  type="button"
                  :aria-label="t('ATTACHMENT_PREVIEW.REMOVE')"
                  class="absolute top-0.5 right-0.5 grid place-content-center size-4 rounded-full bg-n-black/60 hover:bg-n-black/80 text-white"
                  @click.stop="removeAt(index)"
                >
                  <Icon icon="i-lucide-x" class="size-3" />
                </button>
              </div>
            </template>
          </draggable>

          <button
            type="button"
            :aria-label="t('ATTACHMENT_PREVIEW.ADD_MORE')"
            class="shrink-0 size-14 rounded-md border-2 border-dashed border-n-weak grid place-content-center text-n-slate-11 hover:text-wa-teal hover:border-wa-teal"
            @click="emit('add-more')"
          >
            <Icon icon="i-lucide-plus" class="size-6" />
          </button>

          <button
            type="button"
            :aria-label="t('ATTACHMENT_PREVIEW.SEND')"
            :disabled="sending"
            class="ml-2 mr-6 grid place-content-center size-12 rounded-full bg-wa-teal hover:bg-wa-teal-dark text-white transition-transform active:scale-95 disabled:opacity-60 disabled:cursor-not-allowed"
            @click="onSend"
          >
            <Icon
              :icon="sending ? 'i-lucide-loader-circle' : 'i-lucide-send'"
              class="size-5"
              :class="{ 'attachment-send-spin': sending }"
            />
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped lang="scss">
// Multi-file attach: each thumbnail eases in with a small upward pop, staggered
// by its index so a batch cascades in rather than snapping all at once.
.attachment-thumb {
  animation: attachment-thumb-in var(--motion-base, 240ms)
    var(--ease-out-back, ease-out) both;
  animation-delay: calc(var(--thumb-index, 0) * 40ms);
}

@keyframes attachment-thumb-in {
  from {
    opacity: 0;
    transform: translateY(12px) scale(0.82);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

.attachment-send-spin {
  animation: attachment-send-spin var(--motion-drama, 520ms) linear infinite;
}

@keyframes attachment-send-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .attachment-thumb {
    animation-duration: var(--motion-fast, 80ms);
    animation-delay: 0ms;
  }
  .attachment-send-spin {
    animation-duration: 1.4s;
  }
}
</style>
