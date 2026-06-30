<script setup>
defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  chevron: { type: Boolean, default: false },
  interactive: { type: Boolean, default: false },
});
defineEmits(['click']);
// Linha de lista iOS: ícone (leading) + título/subtítulo + trailing + chevron.
// Separador hairline com inset (começa após o ícone), escondido no 1º filho.
defineOptions({ name: 'AiListRow' });
</script>

<template>
  <component
    :is="interactive ? 'button' : 'div'"
    :type="interactive ? 'button' : undefined"
    class="ai-row relative flex gap-3 items-center px-4 py-3 w-full text-left transition-colors first:before:hidden before:absolute before:left-[54px] before:right-0 before:top-0 before:border-t before:border-n-weak before:content-['']"
    :class="interactive ? 'active:bg-n-alpha-1' : ''"
    @click="$emit('click')"
  >
    <span v-if="$slots.leading" class="flex-none"><slot name="leading" /></span>
    <span class="flex-1 min-w-0">
      <span
        v-if="title"
        class="block text-[14.5px] font-semibold text-n-slate-12 truncate"
        >{{ title }}</span
      >
      <span
        v-if="subtitle"
        class="block text-[12.5px] text-n-slate-11 mt-0.5"
        >{{ subtitle }}</span
      >
      <slot />
    </span>
    <slot name="trailing" />
    <span
      v-if="chevron"
      class="flex-none i-lucide-chevron-right text-n-slate-9 size-4"
    />
  </component>
</template>
