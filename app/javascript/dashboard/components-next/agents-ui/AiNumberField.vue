<script setup>
import { computed } from 'vue';
// Campo numérico iOS com steppers (− / +), clamp em [min,max], sufixo opcional.
const props = defineProps({
  modelValue: { type: [Number, String], default: 0 },
  min: { type: Number, default: 0 },
  max: { type: Number, default: 9999 },
  step: { type: Number, default: 1 },
  suffix: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
defineOptions({ name: 'AiNumberField' });
const val = computed(() => Number(props.modelValue) || 0);
const clamp = n => Math.min(props.max, Math.max(props.min, n));
const set = n =>
  emit('update:modelValue', clamp(Number.isNaN(n) ? props.min : n));
const bump = d => set(val.value + d * props.step);
</script>

<template>
  <div
    class="inline-flex overflow-hidden items-stretch rounded-xl border border-n-weak bg-n-solid-1"
  >
    <button
      type="button"
      class="grid px-2.5 place-items-center transition text-n-slate-11 hover:bg-n-alpha-2 active:scale-90"
      @click="bump(-1)"
    >
      <span class="i-lucide-minus size-3.5" />
    </button>
    <div class="flex items-center px-1 border-x border-n-weak">
      <input
        type="number"
        :value="val"
        :min="min"
        :max="max"
        :step="step"
        class="reset-base py-2 w-12 text-sm font-semibold text-center bg-transparent border-0 outline-none text-n-slate-12 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
        @input="set(Number($event.target.value))"
      />
      <span v-if="suffix" class="pr-1.5 text-xs text-n-slate-10">{{
        suffix
      }}</span>
    </div>
    <button
      type="button"
      class="grid px-2.5 place-items-center transition text-n-slate-11 hover:bg-n-alpha-2 active:scale-90"
      @click="bump(1)"
    >
      <span class="i-lucide-plus size-3.5" />
    </button>
  </div>
</template>
