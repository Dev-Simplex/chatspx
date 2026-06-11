<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import Icon from 'next/icon/Icon.vue';

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
]);

const { t } = useI18n();

const activeIndex = ref(0);
const captionLocal = ref(props.caption);

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
  if (props.sending) return;
  emit('send');
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
});

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeyDown);
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
                class="relative shrink-0 size-14 rounded-md overflow-hidden cursor-pointer"
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
                <button
                  type="button"
                  :aria-label="t('ATTACHMENT_PREVIEW.REMOVE')"
                  class="absolute top-0.5 right-0.5 grid place-content-center size-4 rounded-full bg-black/60 hover:bg-black/80 text-white"
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
            <Icon icon="i-lucide-send" class="size-5" />
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
