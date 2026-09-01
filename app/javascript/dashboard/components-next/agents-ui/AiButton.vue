<script setup>
defineProps({
  variant: { type: String, default: 'primary' },
  type: { type: String, default: 'button' },
  disabled: { type: Boolean, default: false },
});
// Botão iOS/big-tech: primary | ghost | subtle. Press com scale (mola).
defineOptions({ name: 'AiButton' });
const CLS = {
  primary: 'bg-n-brand text-white hover:brightness-95',
  ghost: 'bg-n-solid-1 text-n-slate-12 border border-n-weak hover:bg-n-alpha-2',
  subtle: 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3',
  danger: 'bg-n-ruby-9 text-white hover:brightness-95',
};
</script>

<template>
  <button
    :type="type"
    :disabled="disabled"
    class="inline-flex gap-1.5 justify-center items-center px-4 py-2 text-[13px] font-semibold rounded-xl transition-all duration-150 active:scale-95 disabled:opacity-60 disabled:cursor-not-allowed [&_.i-svg]:size-4"
    :class="CLS[variant] || CLS.primary"
  >
    <slot />
  </button>
</template>
