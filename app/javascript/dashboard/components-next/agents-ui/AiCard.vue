<script setup>
// Card de superfície iOS: cabeçalho opcional (leading + título/descrição + ações) + corpo.
// interactive=true → hover-lift + press (para cards clicáveis).
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  interactive: { type: Boolean, default: false },
});
defineOptions({ name: 'AiCard' });
</script>

<template>
  <div
    class="rounded-2xl border shadow-sm backdrop-blur-xl backdrop-saturate-150 border-n-weak bg-n-solid-1/70"
    :class="
      interactive
        ? 'transition-all duration-200 cursor-pointer hover:-translate-y-0.5 hover:shadow-md active:scale-[0.99]'
        : ''
    "
  >
    <div
      v-if="title || description || $slots.leading || $slots.actions"
      class="flex gap-3 items-start px-4 pt-4"
      :class="$slots.default ? 'pb-3' : 'pb-4'"
    >
      <slot name="leading" />
      <div class="flex-1 min-w-0">
        <p v-if="title" class="text-[14px] font-bold text-n-slate-12">
          {{ title }}
        </p>
        <p v-if="description" class="mt-0.5 text-[12.5px] text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <div v-if="$slots.actions" class="flex-none"><slot name="actions" /></div>
    </div>
    <div
      v-if="$slots.default"
      class="px-4"
      :class="
        title || description || $slots.leading || $slots.actions
          ? 'pb-4'
          : 'py-4'
      "
    >
      <slot />
    </div>
  </div>
</template>
