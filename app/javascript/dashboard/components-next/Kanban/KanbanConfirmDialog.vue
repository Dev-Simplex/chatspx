<script setup>
// KANBAN-P1-06 / DoD §35.3: dialog Vue custom para substituir window.confirm.
// Reusável em todo módulo Kanban. Suporta variant 'default' (iris) e 'destructive' (ruby).
import { onMounted, onUnmounted, watch } from 'vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, required: true },
  message: { type: String, default: '' },
  confirmLabel: { type: String, default: '' },
  cancelLabel: { type: String, default: '' },
  variant: { type: String, default: 'default' }, // 'default' | 'destructive'
});

const emit = defineEmits(['confirm', 'cancel']);

const onKeydown = e => {
  if (!props.open) return;
  if (e.key === 'Escape') emit('cancel');
};

watch(
  () => props.open,
  next => {
    if (typeof document === 'undefined') return;
    document.body.style.overflow = next ? 'hidden' : '';
  }
);

onMounted(() => {
  if (typeof window !== 'undefined') {
    window.addEventListener('keydown', onKeydown);
  }
});

onUnmounted(() => {
  if (typeof window !== 'undefined') {
    window.removeEventListener('keydown', onKeydown);
  }
  if (typeof document !== 'undefined') {
    document.body.style.overflow = '';
  }
});
</script>

<template>
  <Teleport v-if="open" to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      role="dialog"
      aria-modal="true"
      aria-labelledby="kanban-confirm-title"
      @click.self="emit('cancel')"
    >
      <div
        class="bg-n-background-1 rounded-2xl p-6 max-w-md w-full mx-4 shadow-2xl"
      >
        <h3
          id="kanban-confirm-title"
          class="text-lg font-semibold text-n-slate-12"
        >
          {{ title }}
        </h3>
        <p v-if="message" class="mt-2 text-sm text-n-slate-11">
          {{ message }}
        </p>
        <div class="mt-6 flex gap-2 justify-end">
          <button
            type="button"
            class="px-4 py-2 rounded-lg text-n-slate-12 hover:bg-n-slate-3 transition-colors"
            @click="emit('cancel')"
          >
            {{ cancelLabel || $t('KANBAN.CONFIRM.CANCEL') }}
          </button>
          <button
            type="button"
            class="px-4 py-2 rounded-lg font-medium transition-colors"
            :class="[
              variant === 'destructive'
                ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                : 'bg-n-iris-9 text-white hover:bg-n-iris-10',
            ]"
            @click="emit('confirm')"
          >
            {{ confirmLabel || $t('KANBAN.CONFIRM.OK') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
