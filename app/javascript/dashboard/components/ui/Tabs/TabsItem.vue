<script setup>
import { computed, inject } from 'vue';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
  name: {
    type: String,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  count: {
    type: Number,
    default: 0,
  },
  showBadge: {
    type: Boolean,
    default: true,
  },
  // eslint-disable-next-line vue/no-unused-properties
  isCompact: {
    type: Boolean,
    default: false,
  },
});

const activeIndex = inject('activeIndex');
const updateActiveIndex = inject('updateActiveIndex');

const active = computed(() => props.index === activeIndex.value);
const getItemCount = computed(() => props.count);

const onTabClick = event => {
  event.preventDefault();
  if (!props.disabled) {
    updateActiveIndex(props.index);
  }
};
</script>

<template>
  <li class="flex-shrink-0">
    <button
      class="flex items-center h-7 px-3 rounded-full text-sm font-medium select-none cursor-pointer transition-all duration-200 border whitespace-nowrap"
      :class="[
        active
          ? 'bg-n-brand/20 text-n-slate-12 font-semibold border-transparent'
          : 'bg-white dark:bg-n-solid-2 text-n-slate-11 border-n-weak hover:bg-n-slate-3/50 hover:border-n-slate-6 active:bg-n-slate-3',
        disabled && 'opacity-50 cursor-not-allowed',
      ]"
      :disabled="disabled"
      @click="onTabClick"
    >
      {{ name }}
      <div
        v-if="showBadge"
        class="rounded-full px-1.5 text-xs min-w-[18px] h-5 inline-flex items-center justify-center ml-1.5"
        :class="[
          active
            ? 'bg-n-brand/25 text-n-slate-12'
            : 'bg-n-slate-3 text-n-slate-10',
        ]"
      >
        <span>
          {{ getItemCount }}
        </span>
      </div>
    </button>
  </li>
</template>
