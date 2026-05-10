<script setup>
import {
  ref,
  useTemplateRef,
  provide,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useResizeObserver } from '@vueuse/core';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

const tabsContainer = useTemplateRef('tabsContainer');
const tabsList = useTemplateRef('tabsList');

const hasOverflowLeft = ref(false);
const hasOverflowRight = ref(false);

const { prefersReducedMotion } = useReducedMotion();
const { t } = useI18n();

const activeIndex = computed({
  get: () => props.index,
  set: newValue => {
    emit('change', newValue);
  },
});

provide('activeIndex', activeIndex);
provide('updateActiveIndex', index => {
  activeIndex.value = index;
});

// Threshold pequeno (4px) para evitar mascarar overflow real,
// mas absorver subpixel rounding.
const OVERFLOW_THRESHOLD = 4;
const SCROLL_STEP = 150;

const computeOverflow = () => {
  const list = tabsList.value;
  if (!list) return;
  const { scrollLeft, scrollWidth, clientWidth } = list;
  hasOverflowLeft.value = scrollLeft > OVERFLOW_THRESHOLD;
  hasOverflowRight.value =
    scrollWidth - clientWidth - scrollLeft > OVERFLOW_THRESHOLD;
};

const scrollBy = delta => {
  const list = tabsList.value;
  if (!list) return;
  list.scrollTo({
    top: 0,
    left: list.scrollLeft + delta,
    behavior: prefersReducedMotion.value ? 'auto' : 'smooth',
  });
};

const onScrollClick = direction => {
  scrollBy(direction === 'left' ? -SCROLL_STEP : SCROLL_STEP);
};

const onListScroll = () => {
  computeOverflow();
};

const onKeydown = event => {
  // Apenas reagir quando o foco está dentro do tablist
  if (!tabsContainer.value) return;
  if (!tabsContainer.value.contains(document.activeElement)) return;

  switch (event.key) {
    case 'ArrowLeft':
      event.preventDefault();
      scrollBy(-SCROLL_STEP);
      break;
    case 'ArrowRight':
      event.preventDefault();
      scrollBy(SCROLL_STEP);
      break;
    case 'Home':
      event.preventDefault();
      tabsList.value?.scrollTo({
        top: 0,
        left: 0,
        behavior: prefersReducedMotion.value ? 'auto' : 'smooth',
      });
      break;
    case 'End':
      event.preventDefault();
      tabsList.value?.scrollTo({
        top: 0,
        left: tabsList.value.scrollWidth,
        behavior: prefersReducedMotion.value ? 'auto' : 'smooth',
      });
      break;
    default:
      break;
  }
};

let stopListResize;
let stopContainerResize;

onMounted(async () => {
  await nextTick();
  computeOverflow();

  // Recalcula em qualquer mudança de tamanho da lista ou do container
  stopListResize = useResizeObserver(tabsList, computeOverflow).stop;
  stopContainerResize = useResizeObserver(tabsContainer, computeOverflow).stop;

  tabsList.value?.addEventListener('scroll', onListScroll, { passive: true });
  window.addEventListener('resize', computeOverflow);
});

onBeforeUnmount(() => {
  stopListResize?.();
  stopContainerResize?.();
  tabsList.value?.removeEventListener('scroll', onListScroll);
  window.removeEventListener('resize', computeOverflow);
});
</script>

<template>
  <div
    ref="tabsContainer"
    class="wa-tabs relative flex items-center w-full"
    @keydown="onKeydown"
  >
    <!-- Fade gradient esquerdo (visível apenas quando há overflow à esquerda) -->
    <div
      v-show="hasOverflowLeft"
      aria-hidden="true"
      class="wa-tabs-fade wa-tabs-fade-left absolute left-0 top-0 bottom-0 w-8 pointer-events-none z-[1]"
    />

    <!-- Chevron esquerdo: somente desktop (md+) e quando há overflow real.
         Posicionado absoluto para não ser > button:first-child do .wa-tabs. -->
    <button
      v-show="hasOverflowLeft"
      type="button"
      tabindex="-1"
      :aria-label="t('TABS.SCROLL_LEFT')"
      class="wa-tabs-chevron wa-tabs-chevron-left hidden md:flex absolute left-0 top-1/2 -translate-y-1/2 z-[2] items-center justify-center w-6 h-6 rounded-full opacity-45 hover:opacity-90 transition-opacity cursor-pointer bg-transparent border-0"
      @click="onScrollClick('left')"
    >
      <span class="i-lucide-chevron-left size-4" />
    </button>

    <ul
      ref="tabsList"
      role="tablist"
      class="flex items-center gap-1.5 px-3 py-1.5 list-none mb-0 overflow-x-auto no-scrollbar flex-1 min-w-0 scroll-smooth"
    >
      <slot />
    </ul>

    <!-- Chevron direito: só desktop, só quando overflow à direita. -->
    <button
      v-show="hasOverflowRight"
      type="button"
      tabindex="-1"
      :aria-label="t('TABS.SCROLL_RIGHT')"
      class="wa-tabs-chevron wa-tabs-chevron-right hidden md:flex absolute right-0 top-1/2 -translate-y-1/2 z-[2] items-center justify-center w-6 h-6 rounded-full opacity-45 hover:opacity-90 transition-opacity cursor-pointer bg-transparent border-0"
      @click="onScrollClick('right')"
    >
      <span class="i-lucide-chevron-right size-4" />
    </button>

    <!-- Fade gradient direito -->
    <div
      v-show="hasOverflowRight"
      aria-hidden="true"
      class="wa-tabs-fade wa-tabs-fade-right absolute right-0 top-0 bottom-0 w-8 pointer-events-none z-[1]"
    />
  </div>
</template>
