<script setup>
import { ref, onBeforeUnmount } from 'vue';
// Menu de ações iOS (substitui DropdownMenu legado). items: [{ value, label, icon, danger }].
defineProps({
  items: { type: Array, default: () => [] },
  align: { type: String, default: 'right' }, // right | left
});
const emit = defineEmits(['select']);
defineOptions({ name: 'AiDropdown' });
const open = ref(false);
const root = ref(null);
function onDoc(e) {
  if (root.value && !root.value.contains(e.target)) {
    open.value = false;
    document.removeEventListener('click', onDoc, true);
  }
}
function close() {
  open.value = false;
  document.removeEventListener('click', onDoc, true);
}
const toggle = () => {
  open.value = !open.value;
  if (open.value) document.addEventListener('click', onDoc, true);
  else close();
};
const pick = it => {
  close();
  emit('select', it.value);
};
onBeforeUnmount(() => document.removeEventListener('click', onDoc, true));
</script>

<template>
  <div ref="root" class="inline-block relative">
    <button
      type="button"
      class="grid place-items-center rounded-lg transition size-8 text-n-slate-11 hover:bg-n-alpha-2 active:scale-95"
      @click.stop="toggle"
    >
      <slot name="trigger">
        <span class="i-lucide-more-horizontal size-4" />
      </slot>
    </button>
    <Transition name="ai-dd">
      <div
        v-if="open"
        class="absolute top-full z-50 mt-1 py-1 min-w-[184px] rounded-xl border shadow-xl border-n-weak bg-n-solid-1"
        :class="align === 'left' ? 'left-0' : 'right-0'"
      >
        <button
          v-for="it in items"
          :key="it.value"
          type="button"
          class="flex gap-2.5 items-center px-3 py-2 w-full text-left text-[13px] font-medium transition hover:bg-n-alpha-2"
          :class="it.danger ? 'text-n-ruby-11' : 'text-n-slate-12'"
          @click="pick(it)"
        >
          <span v-if="it.icon" :class="it.icon" class="size-4" />
          {{ it.label }}
        </button>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.ai-dd-enter-active {
  transition: all 0.16s cubic-bezier(0.22, 1, 0.36, 1);
}
.ai-dd-enter-from {
  opacity: 0;
  transform: translateY(-4px) scale(0.97);
}
</style>
