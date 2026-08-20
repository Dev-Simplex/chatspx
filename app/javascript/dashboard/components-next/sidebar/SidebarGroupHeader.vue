<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';
import LordIconIcon from 'next/icon/LordIconIcon.vue';
import { LORDICON } from 'dashboard/constants/lordicons';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
  isCollapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
const count = computed(() =>
  dynamicCount.value > 99 ? '99+' : dynamicCount.value
);
</script>

<template>
  <component
    :is="to ? 'router-link' : 'div'"
    v-tooltip.right="isCollapsed ? label : undefined"
    data-hover-host
    :data-sidebar-active="
      String((isActive && !hasActiveChild) || hasActiveChild)
    "
    class="icon-animated flex items-center gap-2 px-1.5 py-1 rounded-lg h-8 min-w-0 transition-colors duration-150"
    role="button"
    draggable="false"
    :to="to"
    :class="{
      'text-n-slate-12 bg-n-alpha-2 font-medium [&_svg]:opacity-100 [&_svg]:text-n-brand':
        isActive && !hasActiveChild,
      'text-n-slate-12 font-medium [&_svg]:opacity-100 [&_svg]:text-n-brand':
        hasActiveChild,
      'text-n-slate-11 hover:bg-n-alpha-2 [&_svg]:opacity-60':
        !isActive && !hasActiveChild,
    }"
    @click.stop="emit('toggle')"
  >
    <div
      v-if="icon"
      class="relative flex items-center"
      :class="{ 'gap-2': !isCollapsed }"
    >
      <Icon v-if="icon" :icon="icon" class="size-4" />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2 animate-scale-in"
      />
    </div>
    <div
      class="flex items-center gap-1.5 flex-grow justify-between min-w-0 flex-1"
    >
      <span
        class="truncate"
        :class="{
          'text-body-main': !isActive,
          'font-medium text-sm': isActive || hasActiveChild,
        }"
      >
        {{ label }}
      </span>
      <span
        v-if="dynamicCount && !expandable"
        class="inline-grid h-5 min-w-5 place-items-center rounded-full bg-n-slate-4 px-1 text-xxs font-medium leading-3 text-n-slate-12 dark:bg-n-slate-5 flex-shrink-0"
      >
        {{ count }}
      </span>
    </div>
    <LordIconIcon
      v-if="expandable && !isCollapsed"
      :src="LORDICON.chevronDown.idle"
      :src-active="LORDICON.chevronDown.active"
      :family="LORDICON.chevronDown.family"
      fallback-lucide="i-lucide-chevron-down"
      :size="12"
      class="transition-transform duration-200"
      :class="{ 'rotate-180': isExpanded }"
      @click.stop="emit('toggle')"
    />
  </component>
</template>
