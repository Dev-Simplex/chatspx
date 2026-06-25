<script setup>
import { computed, inject, useTemplateRef } from 'vue';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';
import NumberFlow from '@number-flow/vue';

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
  // Opt-in odometer animation on the badge count (D8). Off by default so every
  // other tab in the app keeps the plain number.
  animatedCount: {
    type: Boolean,
    default: false,
  },
});

const activeIndex = inject('activeIndex');
const updateActiveIndex = inject('updateActiveIndex');

const tabButton = useTemplateRef('tabButton');
const { prefersReducedMotion } = useReducedMotion();

const active = computed(() => props.index === activeIndex.value);
const getItemCount = computed(() => props.count);

const onTabClick = event => {
  event.preventDefault();
  if (!props.disabled) {
    updateActiveIndex(props.index);
  }
};

const onTabFocus = () => {
  if (!tabButton.value) return;
  // Garante que a tab focada seja visível mesmo se cortada por overflow.
  tabButton.value.scrollIntoView({
    inline: 'nearest',
    block: 'nearest',
    behavior: prefersReducedMotion.value ? 'auto' : 'smooth',
  });
};
</script>

<template>
  <li class="flex-shrink-0" role="presentation">
    <button
      ref="tabButton"
      role="tab"
      :title="name"
      :aria-selected="active ? 'true' : 'false'"
      :tabindex="active ? 0 : -1"
      class="wa-tab-item flex items-center h-7 px-3 rounded-full text-sm font-medium select-none cursor-pointer transition-all duration-200 border border-transparent whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/60"
      :class="[
        active ? 'active font-semibold' : '',
        disabled && 'opacity-50 cursor-not-allowed',
      ]"
      :disabled="disabled"
      @click="onTabClick"
      @focus="onTabFocus"
    >
      <span
        v-if="icon"
        :class="icon"
        class="wa-tab-item__icon size-3.5 mr-1.5 shrink-0"
        aria-hidden="true"
      />
      <span class="wa-tab-item__label">{{ name }}</span>
      <div
        v-if="showBadge"
        class="wa-tab-item__badge rounded-full px-1.5 text-xs min-w-[18px] h-5 inline-flex items-center justify-center ml-1.5"
      >
        <NumberFlow
          v-if="animatedCount && !prefersReducedMotion"
          :value="getItemCount"
        />
        <span v-else>
          {{ getItemCount }}
        </span>
      </div>
    </button>
  </li>
</template>
