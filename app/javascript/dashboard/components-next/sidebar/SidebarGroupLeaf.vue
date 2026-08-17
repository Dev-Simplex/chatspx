<script setup>
import { isVNode, computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import Policy from 'dashboard/components/policy.vue';
import { useSidebarContext } from './provider';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  label: { type: String, required: true },
  to: { type: [String, Object], required: true },
  icon: { type: [String, Object], default: null },
  active: { type: Boolean, default: false },
  component: { type: Function, default: null },
  count: { type: Number, default: 0 },
  highlight: { type: Boolean, default: false },
  isCollapsed: { type: Boolean, default: false },
  badgeCount: { type: [Number, String], default: 0 },
  hideTreeLine: { type: Boolean, default: false },
  thinTreeLine: { type: Boolean, default: false },
});

const { resolvePermissions, resolveFeatureFlag } = useSidebarContext();

const shouldRenderComponent = computed(() => {
  return typeof props.component === 'function' || isVNode(props.component);
});

const CustomLeaf = () => {
  if (isVNode(props.component)) return props.component;

  return props.component({
    label: props.label,
    icon: props.icon,
    active: props.active,
    isCollapsed: props.isCollapsed,
    badgeCount: props.badgeCount,
  });
};

const displayCount = computed(() => (props.count > 99 ? '99+' : props.count));
// Tree-line connector per leaf: vertical line (::before) + rounded elbow on the
// last child (::after). Logical props (start / border-s / rounded-es)
const TREE_CONNECTOR =
  "child-item before:content-[''] before:absolute before:start-0 before:w-0.5 before:h-full before:bg-n-slate-4 first:before:rounded-t last:before:h-1/5 last:after:content-[''] last:after:absolute last:after:start-0 last:after:bottom-[calc(50%_-_2px)] last:after:h-3 last:after:w-2.5 last:after:border-b-2 last:after:border-s-2 last:after:rounded-es last:after:border-n-slate-4";
</script>

<template>
  <Policy
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="py-0.5 ps-2 ms-3 relative text-n-slate-11 min-w-0"
    :class="{
      [TREE_CONNECTOR]: !hideTreeLine,
      'before:!w-px last:after:!border-b last:after:!border-s':
        !hideTreeLine && thinTreeLine,
    }"
  >
    <component
      :is="to ? 'router-link' : 'div'"
      :to="to"
      data-hover-host
      :data-sidebar-active="String(active)"
      :title="label"
      class="icon-animated flex h-8 items-center gap-2 px-2 py-1 rounded-lg ltr:hover:bg-gradient-to-r rtl:hover:bg-gradient-to-l from-transparent via-n-slate-3/70 to-n-slate-3/70 group min-w-0 transition-colors duration-150"
      :class="{
        'text-n-slate-12 bg-n-alpha-2 active [&_svg]:opacity-100 [&_svg]:text-n-brand':
          active,
        'ltr:border-l-2 rtl:border-r-2 border-n-amber-7 bg-n-amber-5/25 ring-1 ring-n-amber-6/50 ring-inset animate-sidebar-attention motion-reduce:animate-none':
          highlight && !active,
      }"
    >
      <CustomLeaf v-if="shouldRenderComponent" />
      <template v-else>
        <span v-if="icon" class="size-4 grid place-content-center rounded-full">
          <Icon :icon="icon" class="size-4 inline-block" />
        </span>
        <div class="flex-1 truncate min-w-0 text-sm">{{ label }}</div>
        <div v-if="count > 0" class="relative flex-shrink-0 my-0 mx-1">
          <span
            v-if="highlight"
            class="absolute inset-0 rounded-md bg-n-amber-6 animate-ping opacity-60 motion-reduce:animate-none"
            aria-hidden="true"
          />
          <div
            class="relative rounded-md h-5 flex items-center justify-center text-xxs font-semibold px-1 py-0 min-w-[20px]"
            :class="[
              active && highlight
                ? 'bg-n-amber-5/30 dark:bg-n-amber-5/40 text-n-amber-11'
                : active
                  ? 'bg-n-brand/10 dark:bg-n-brand/20 text-n-teal-text'
                  : 'bg-n-alpha-black2 dark:bg-n-solid-3 text-n-slate-11',
            ]"
          >
            <span>{{ displayCount }}</span>
          </div>
        </div>
        <SidebarUnreadBadge v-else :count="badgeCount" />
      </template>
    </component>
  </Policy>
</template>
