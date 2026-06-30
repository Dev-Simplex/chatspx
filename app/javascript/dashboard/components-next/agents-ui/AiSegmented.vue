<script setup>
// Segmented control iOS com thumb deslizante (mola). options: [{value,label}]
import { ref, watch, onMounted, nextTick } from 'vue';

const props = defineProps({
  options: { type: Array, default: () => [] },
  modelValue: { type: [String, Number], default: '' },
});
const emit = defineEmits(['update:modelValue']);
defineOptions({ name: 'AiSegmented' });
const root = ref(null);
const thumb = ref(null);

const move = async () => {
  await nextTick();
  const r = root.value;
  const th = thumb.value;
  if (!r || !th) return;
  const on = r.querySelector('[data-on="true"]');
  if (!on || !on.offsetWidth) return;
  th.style.width = `${on.offsetWidth}px`;
  th.style.height = `${on.offsetHeight}px`;
  th.style.transform = `translate(${on.offsetLeft}px, ${on.offsetTop}px)`;
};

const select = v => {
  emit('update:modelValue', v);
  move();
};

onMounted(move);
watch(() => props.modelValue, move);
watch(() => props.options, move, { deep: true });
</script>

<template>
  <div
    ref="root"
    class="inline-flex relative gap-0.5 p-0.5 rounded-[10px] border border-n-weak bg-n-alpha-1"
  >
    <div
      ref="thumb"
      class="absolute top-0 left-0 rounded-lg shadow-sm pointer-events-none bg-n-solid-1 transition-[transform,width,height] duration-300 ease-[cubic-bezier(.34,1.56,.64,1)]"
    />
    <button
      v-for="o in options"
      :key="o.value"
      type="button"
      :data-on="o.value === modelValue"
      class="relative z-[1] px-4 py-1.5 text-[12.5px] font-semibold rounded-lg transition-colors"
      :class="o.value === modelValue ? 'text-n-slate-12' : 'text-n-slate-11'"
      @click="select(o.value)"
    >
      {{ o.label }}
    </button>
  </div>
</template>
