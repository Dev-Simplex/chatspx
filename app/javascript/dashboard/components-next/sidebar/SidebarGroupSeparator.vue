<script setup>
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  label: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    default: '',
  },
  collapsible: {
    type: Boolean,
    default: false,
  },
  isExpanded: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);
</script>

<template>
  <component
    :is="props.collapsible ? 'button' : 'div'"
    :type="props.collapsible ? 'button' : undefined"
    :aria-expanded="props.collapsible ? props.isExpanded : undefined"
    class="flex items-center gap-2 px-2 py-1.5 rounded-lg h-8 text-n-slate-10 select-none"
    :class="[
      props.collapsible
        ? 'cursor-pointer w-full text-left bg-transparent border-0'
        : 'pointer-events-none',
    ]"
    @click="props.collapsible ? emit('toggle') : undefined"
  >
    <Icon v-if="props.icon" :icon="props.icon" class="size-4" />
    <span class="text-xs font-medium leading-5 flex-grow">
      {{ props.label }}
    </span>
    <span
      v-if="props.collapsible"
      class="i-lucide-chevron-down size-3 transition-transform flex-shrink-0"
      :class="{ 'rotate-180': props.isExpanded }"
    />
  </component>
</template>
