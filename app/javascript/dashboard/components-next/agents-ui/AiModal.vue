<script setup>
// Modal de formulário iOS: teleport, scrim blur, mola, header + corpo + rodapé (slot footer).
defineProps({
  modelValue: { type: Boolean, default: false },
  title: { type: String, default: '' },
  width: { type: Number, default: 480 },
});
const emit = defineEmits(['update:modelValue']);
defineOptions({ name: 'AiModal' });
const close = () => emit('update:modelValue', false);
</script>

<template>
  <Teleport to="body">
    <Transition name="ai-modal">
      <div
        v-if="modelValue"
        class="grid fixed inset-0 z-[100] place-items-center p-4 bg-n-black/40 backdrop-blur-sm"
        @click.self="close"
      >
        <div
          class="w-full ai-modal-panel rounded-[20px] border border-n-weak bg-n-solid-1 shadow-2xl"
          :style="{ maxWidth: `${width}px` }"
        >
          <div class="flex gap-3 items-center px-5 py-4 border-b border-n-weak">
            <span class="flex-1 text-[16px] font-bold text-n-slate-12">{{
              title
            }}</span>
            <button
              type="button"
              class="grid place-items-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2"
              @click="close"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
          <div class="p-5"><slot /></div>
          <div
            v-if="$slots.footer"
            class="flex gap-2 justify-end px-5 py-4 border-t border-n-weak"
          >
            <slot name="footer" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.ai-modal-enter-active,
.ai-modal-leave-active {
  transition: opacity 0.25s ease;
}
.ai-modal-enter-from,
.ai-modal-leave-to {
  opacity: 0;
}
.ai-modal-enter-active .ai-modal-panel {
  transition: transform 0.34s cubic-bezier(0.34, 1.56, 0.64, 1);
}
.ai-modal-enter-from .ai-modal-panel {
  transform: translateY(16px) scale(0.98);
}
@media (prefers-reduced-motion: reduce) {
  .ai-modal-enter-active .ai-modal-panel {
    transition: none;
  }
}
</style>
