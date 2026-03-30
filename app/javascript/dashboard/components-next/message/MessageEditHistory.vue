<script setup>
import { onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  previousContent: { type: String, default: '' },
  editedBy: { type: Object, default: null },
  editedAt: { type: String, default: '' },
  // { top, left } from getBoundingClientRect of the trigger button
  triggerRect: { type: Object, default: null },
});

const emit = defineEmits(['close']);
const { t } = useI18n();

const POPOVER_WIDTH = 256; // w-64
const POPOVER_GAP = 8;

const popoverStyle = computed(() => {
  // Use clientWidth (excludes scrollbar) for accurate clamping
  const viewportWidth =
    document.documentElement.clientWidth || window.innerWidth;

  if (!props.triggerRect) {
    return {
      position: 'fixed',
      top: '-9999px',
      left: '-9999px',
      visibility: 'hidden',
    };
  }

  const { top, left, width } = props.triggerRect;
  // Center horizontally on the button, clamp strictly inside viewport
  let x = left + width / 2 - POPOVER_WIDTH / 2;
  x = Math.max(8, Math.min(x, viewportWidth - POPOVER_WIDTH - 8));

  return {
    position: 'fixed',
    top: `${top - POPOVER_GAP}px`,
    left: `${x}px`,
    transform: 'translateY(-100%)',
    width: `${POPOVER_WIDTH}px`,
    maxWidth: `${viewportWidth - 16}px`,
  };
});

function formattedDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function handleOutsideClick(e) {
  if (!e.target.closest('.edit-history-popover')) {
    emit('close');
  }
}

onMounted(() => document.addEventListener('click', handleOutsideClick, true));
onUnmounted(() =>
  document.removeEventListener('click', handleOutsideClick, true)
);
</script>

<template>
  <Teleport to="body">
    <div
      class="edit-history-popover z-[9999] rounded-lg shadow-xl border border-n-strong bg-n-background p-3 text-sm overflow-hidden"
      :style="popoverStyle"
    >
      <div class="flex items-center justify-between mb-2">
        <span
          class="font-medium text-n-slate-12 text-xs uppercase tracking-wide"
        >
          {{ t('CONVERSATION.EDIT_HISTORY.TITLE') }}
        </span>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 transition-colors"
          @click.stop="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </div>

      <p
        class="text-n-slate-11 whitespace-pre-wrap break-words leading-relaxed mb-3"
      >
        {{ previousContent || t('CONVERSATION.EDIT_HISTORY.NO_CONTENT') }}
      </p>

      <div class="border-t border-n-strong pt-2 space-y-0.5">
        <p v-if="editedBy?.name" class="text-xs text-n-slate-10">
          {{
            t('CONVERSATION.EDIT_HISTORY.EDITED_BY', { name: editedBy.name })
          }}
        </p>
        <p v-if="editedAt" class="text-xs text-n-slate-10">
          {{ formattedDate(editedAt) }}
        </p>
      </div>
    </div>
  </Teleport>
</template>
