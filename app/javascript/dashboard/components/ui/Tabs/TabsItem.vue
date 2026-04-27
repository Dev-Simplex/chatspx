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
  icon: {
    type: String,
    default: '',
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
      class="wa-tab-item flex items-center h-7 px-3 rounded-full text-sm font-medium select-none cursor-pointer transition-all duration-200 border border-transparent whitespace-nowrap"
      :class="[
        active ? 'active font-semibold' : '',
        disabled && 'opacity-50 cursor-not-allowed',
      ]"
      :disabled="disabled"
      @click="onTabClick"
    >
      <span
        v-if="icon"
        :class="icon"
        class="size-3.5 mr-1.5 shrink-0"
        aria-hidden="true"
      />
      {{ name }}
      <div
        v-if="showBadge"
        class="wa-tab-item__badge rounded-full px-1.5 text-xs min-w-[18px] h-5 inline-flex items-center justify-center ml-1.5"
      >
        <span>
          {{ getItemCount }}
        </span>
      </div>
    </button>
  </li>
</template>
