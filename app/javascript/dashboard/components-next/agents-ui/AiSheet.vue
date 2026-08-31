<script setup>
defineProps({
  modelValue: { type: Boolean, default: false },
  title: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
// Sheet/modal iOS: teleport, scrim com blur, grabber, entrada com mola.
defineOptions({ name: 'AiSheet' });
const close = () => emit('update:modelValue', false);
</script>

<template>
  <Teleport to="body">
    <Transition name="ai-sheet">
      <div
        v-if="modelValue"
        class="grid fixed inset-0 z-[100] place-items-center p-4 bg-n-black/40 backdrop-blur-sm"
        @click.self="close"
      >
        <div
          class="ai-sheet-panel w-[min(680px,92vw)] max-h-[86vh] overflow-auto rounded-[20px] border border-n-weak bg-n-solid-1 shadow-2xl"
        >
          <div
            class="mx-auto mt-2.5 mb-1 h-[5px] w-9 rounded-full bg-n-slate-5"
          />
          <div class="flex gap-3 items-center px-5 py-3 border-b border-n-weak">
            <span
              class="flex-1 text-[15px] font-bold truncate text-n-slate-12"
              >{{ title }}</span
            >
            <slot name="actions" />
            <button
              type="button"
              class="grid place-items-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2"
              @click="close"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
          <div class="p-5"><slot /></div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.ai-sheet-enter-active,
.ai-sheet-leave-active {
  transition: opacity 0.25s ease;
}
.ai-sheet-enter-from,
.ai-sheet-leave-to {
  opacity: 0;
}
.ai-sheet-enter-active .ai-sheet-panel {
  transition: transform 0.34s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.ai-sheet-enter-from .ai-sheet-panel {
  transform: translateY(16px) scale(0.98);
}
</style>
