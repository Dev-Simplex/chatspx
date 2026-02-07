<script setup>
import { isVNode, computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import Policy from 'dashboard/components/policy.vue';
import { useSidebarContext } from './provider';

const props = defineProps({
  label: { type: String, required: true },
  to: { type: [String, Object], required: true },
  icon: { type: [String, Object], default: null },
  active: { type: Boolean, default: false },
  component: { type: Function, default: null },
  count: { type: Number, default: 0 },
  highlight: { type: Boolean, default: false },
  isCollapsed: { type: Boolean, default: false },
});

const { resolvePermissions, resolveFeatureFlag } = useSidebarContext();

const shouldRenderComponent = computed(() => {
  return typeof props.component === 'function' || isVNode(props.component);
});

const displayCount = computed(() =>
  props.count > 99 ? '99+' : props.count
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Policy
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="py-0.5 ltr:pl-3 rtl:pr-3 rtl:mr-3 ltr:ml-3 relative text-n-slate-11 child-item before:bg-n-slate-4 after:bg-transparent after:border-n-slate-4 before:left-0 rtl:before:right-0"
  >
    <component
      :is="to ? 'router-link' : 'div'"
      :to="to"
      :title="isCollapsed ? label : undefined"
      class="flex h-8 items-center rounded-lg hover:bg-gradient-to-r from-transparent via-n-slate-3/70 to-n-slate-3/70 group"
      :class="[
        {
          'justify-center px-2': isCollapsed,
          'gap-2 px-2 py-1 max-w-[9.438rem]': !isCollapsed,
        },
        {
          'text-n-teal-text bg-n-alpha-2 active': active,
          'ltr:border-l-2 rtl:border-r-2 border-n-amber-7 bg-n-amber-5/25 ring-1 ring-n-amber-6/50 ring-inset animate-sidebar-attention motion-reduce:animate-none':
            highlight && !active,
        },
      ]"
    >
      <component
        :is="component"
        v-if="shouldRenderComponent"
        :label
        :icon
        :active
        :is-collapsed="isCollapsed"
      />
      <template v-else>
        <Icon v-if="icon" :icon="icon" class="size-4 inline-block" />
        <div v-if="!isCollapsed" class="flex-1 truncate min-w-0">
          {{ label }}
        </div>
        <div
          v-if="!isCollapsed && count > 0"
          class="relative flex-shrink-0 my-0 mx-1"
        >
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
      </template>
    </component>
  </Policy>
</template>
