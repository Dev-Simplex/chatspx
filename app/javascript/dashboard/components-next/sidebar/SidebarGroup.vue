<script setup>
import { computed, onMounted, onUnmounted, watch, nextTick, ref } from 'vue';
import { useSidebarContext, usePopoverState } from './provider';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Policy from 'dashboard/components/policy.vue';
import Icon from 'next/icon/Icon.vue';
import SidebarGroupHeader from './SidebarGroupHeader.vue';
import SidebarGroupLeaf from './SidebarGroupLeaf.vue';
import SidebarSubGroup from './SidebarSubGroup.vue';
import SidebarGroupEmptyLeaf from './SidebarGroupEmptyLeaf.vue';
import SidebarCollapsedPopover from './SidebarCollapsedPopover.vue';

const props = defineProps({
  name: { type: String, required: true },
  label: { type: String, required: true },
  icon: { type: [String, Object, Function], default: null },
  to: { type: Object, default: null },
  activeOn: { type: Array, default: () => [] },
  children: { type: Array, default: undefined },
  getterKeys: { type: Object, default: () => ({}) },
});

const {
  expandedItem,
  setExpandedItem,
  resolvePath,
  resolvePermissions,
  resolveFeatureFlag,
  isAllowed,
  isCollapsed,
  isResizing,
} = useSidebarContext();

const {
  activePopover,
  setActivePopover,
  closeActivePopover,
  scheduleClose,
  cancelClose,
} = usePopoverState();

const navigableChildren = computed(() => {
  return props.children?.flatMap(child => child.children || child) || [];
});

const route = useRoute();
const router = useRouter();
const isExpanded = computed(() => expandedItem.value === props.name);
const isExpandable = computed(() => props.children);
const hasChildren = computed(
  () => Array.isArray(props.children) && props.children.length > 0
);

// Use shared popover state - only one popover can be open at a time
const isPopoverOpen = computed(() => activePopover.value === props.name);
const triggerRef = ref(null);
const triggerRect = ref({ top: 0, left: 0, bottom: 0, right: 0 });
// The sort dropdown teleports outside the popover; keep the popover open while
// it is showing so moving the cursor onto it does not close everything.
const isSortMenuOpen = ref(false);

const openPopover = () => {
  if (triggerRef.value) {
    const rect = triggerRef.value.getBoundingClientRect();
    triggerRect.value = {
      top: rect.top,
      left: rect.left,
      bottom: rect.bottom,
      right: rect.right,
    };
  }
  setActivePopover(props.name);
};

const closePopover = () => {
  if (activePopover.value === props.name) {
    closeActivePopover();
  }
};

const handleMouseEnter = () => {
  if (!hasChildren.value || isResizing.value) return;
  cancelClose();
  openPopover();
};

const handleMouseLeave = () => {
  if (!hasChildren.value || isSortMenuOpen.value) return;
  scheduleClose(200);
};

const handlePopoverMouseEnter = () => {
  cancelClose();
};

const handlePopoverMouseLeave = () => {
  if (isSortMenuOpen.value) return;
  scheduleClose(100);
};

const handleSortToggle = isOpen => {
  isSortMenuOpen.value = isOpen;
  cancelClose();
};

// Close popover when mouse leaves the window
const handleWindowBlur = () => {
  closeActivePopover();
};

const hasAccessibleSubChildren = child => {
  return child.children?.some(
    subChild => subChild.to && isAllowed(subChild.to)
  );
};

const visibleChildren = computed(() => {
  if (!hasChildren.value) return [];

  return props.children.filter(child => {
    if (child.children) return hasAccessibleSubChildren(child);

    return child.to && isAllowed(child.to);
  });
});

const accessibleItems = computed(() => {
  if (!hasChildren.value) return [];

  return visibleChildren.value
    .flatMap(child => child.children || child)
    .filter(child => child.to && isAllowed(child.to));
});

const hasAccessibleChildren = computed(() => {
  return visibleChildren.value.length > 0;
});

const isLastVisibleChild = child => {
  const lastChild = visibleChildren.value[visibleChildren.value.length - 1];
  return lastChild === child;
};

const isActive = computed(() => {
  if (props.to) {
    if (route.path === resolvePath(props.to)) return true;

    return props.activeOn.includes(route.name);
  }

  return false;
});

// We could use the RouterLink isActive too, but our routes are not always
// nested correctly, so we need to check the active state ourselves
// TODO: Audit the routes and fix the nesting and remove this
const activeChild = computed(() => {
  if (
    route.name === 'conversation_unattended' ||
    route.name === 'conversation_through_unattended'
  ) {
    const qt = route.query.assignee_type;
    const unattendedChildren = navigableChildren.value.filter(
      child => child.to?.name === 'conversation_unattended'
    );
    if (!qt || qt === 'me') {
      const mineMatch = unattendedChildren.find(
        child => !child.to?.query?.assignee_type
      );
      if (mineMatch) return mineMatch;
    }
    const queryMatch = unattendedChildren.find(
      child => child.to?.query?.assignee_type === qt
    );
    if (queryMatch) return queryMatch;
  }

  // Unread children are also distinguished only by ?assignee_type, but unlike
  // unattended their default (no query) is "All", not "Mine" (see
  // unreadViewHelper.defaultAssigneeTab). Each child has an explicit
  // assignee_type, so default an empty query to 'all' before matching.
  if (
    route.name === 'conversation_unread' ||
    route.name === 'conversation_through_unread'
  ) {
    const qt = route.query.assignee_type || 'all';
    const unreadMatch = navigableChildren.value.find(
      child =>
        child.to?.name === 'conversation_unread' &&
        child.to?.query?.assignee_type === qt
    );
    if (unreadMatch) return unreadMatch;
  }

  const pathSame = navigableChildren.value.find(
    child => child.to && route.path === resolvePath(child.to)
  );
  if (pathSame) return pathSame;

  // Rank the activeOn Prop higher than the path match
  // There will be cases where the path name is the same but the params are different
  // So we need to rank them based on the params
  // For example, contacts segment list in the sidebar effectively has the same name
  // But the params are different
  const activeOnPages = navigableChildren.value.filter(child =>
    child.activeOn?.includes(route.name)
  );

  if (activeOnPages.length > 0) {
    const rankedPage = activeOnPages.find(child => {
      return Object.keys(child.to.params || {})
        .map(key => {
          return String(child.to.params[key]) === String(route.params[key]);
        })
        .every(match => match);
    });

    // If there is no ranked page, return the first activeOn page anyway
    // Since this takes higher precedence over the path match
    // This is not perfect, ideally we should rank each route based on all the techniques
    // and then return the highest ranked one
    // But this is good enough for now
    return rankedPage ?? activeOnPages[0];
  }

  return navigableChildren.value.find(child => {
    if (!child.to) return false;
    const childPath = resolvePath(child.to);
    return route.path === childPath || route.path.startsWith(`${childPath}/`);
  });
});

const hasActiveChild = computed(() => {
  return activeChild.value !== undefined;
});

// useMapGetter deve ser chamado no nível superior, não dentro de computed
const badgeGetter = props.getterKeys?.badge
  ? useMapGetter(props.getterKeys.badge)
  : null;
const countGetter = props.getterKeys?.count
  ? useMapGetter(props.getterKeys.count)
  : null;

const showBadge = computed(() => {
  return badgeGetter?.value ?? false;
});

const countValue = computed(() => Number(countGetter?.value) || 0);

const countLabel = computed(() => {
  const v = countValue.value;
  if (v <= 0) return null;
  return v > 99 ? '99+' : String(v);
});

const handleCollapsedClick = () => {
  if (hasChildren.value && hasAccessibleChildren.value) {
    const firstItem = accessibleItems.value[0];
    router.push(firstItem.to);
  }
};

const toggleTrigger = () => {
  if (
    hasAccessibleChildren.value &&
    !isExpanded.value &&
    !hasActiveChild.value
  ) {
    // if not already expanded, navigate to the first child
    const firstItem = accessibleItems.value[0];
    router.push(firstItem.to);
  }
  setExpandedItem(props.name);
};

// WA-style fidelity: only the Conversation group auto-expands on mount when
// its child is active. Other groups stay collapsed unless the user clicks
// them open, matching WhatsApp Web's behaviour.
const AUTO_EXPANDABLE_GROUPS = ['Conversation'];

onMounted(async () => {
  await nextTick();
  if (hasActiveChild.value && AUTO_EXPANDABLE_GROUPS.includes(props.name)) {
    setExpandedItem(props.name);
  }
  window.addEventListener('blur', handleWindowBlur);
  document.addEventListener('mouseleave', handleWindowBlur);
});

onUnmounted(() => {
  window.removeEventListener('blur', handleWindowBlur);
  document.removeEventListener('mouseleave', handleWindowBlur);
});

watch(
  hasActiveChild,
  hasNewActiveChild => {
    if (
      hasNewActiveChild &&
      !isExpanded.value &&
      AUTO_EXPANDABLE_GROUPS.includes(props.name)
    ) {
      setExpandedItem(props.name);
    }
  },
  { once: true }
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Policy
    v-if="!hasChildren || hasAccessibleChildren"
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="grid gap-1 text-sm cursor-pointer select-none min-w-0"
  >
    <!-- Collapsed State -->
    <template v-if="isCollapsed">
      <div
        class="relative"
        @mouseenter="handleMouseEnter"
        @mouseleave="handleMouseLeave"
      >
        <component
          :is="to && !hasChildren ? 'router-link' : 'button'"
          ref="triggerRef"
          v-tooltip.right="hasChildren ? undefined : label"
          data-hover-host
          :data-sidebar-active="String(isActive || hasActiveChild)"
          :to="to && !hasChildren ? to : undefined"
          type="button"
          class="flex items-center justify-center size-10 rounded-lg"
          :class="{
            'text-n-slate-12 bg-n-alpha-2 [&_svg]:opacity-100 [&_svg]:text-n-brand':
              isActive || hasActiveChild,
            'text-n-slate-11 hover:bg-n-alpha-2 [&_svg]:opacity-60':
              !isActive && !hasActiveChild,
          }"
          @click="hasChildren ? handleCollapsedClick() : undefined"
        >
          <div v-if="icon" class="relative flex items-center">
            <Icon v-if="icon" :icon="icon" class="size-4" />
            <!-- Badge vermelho com contador (notificações, mensagens) -->
            <span
              v-if="countLabel"
              class="absolute -top-1.5 ltr:-right-2 rtl:-left-2 min-w-[18px] h-[18px] px-1 rounded-full bg-[#ef4444] text-white text-[10px] font-bold flex items-center justify-center border border-n-solid-2 leading-none animate-scale-in pointer-events-none"
            >
              {{ countLabel }}
            </span>
            <!-- Badge dot (sem contador) — só se NÃO tem countLabel -->
            <span
              v-else-if="showBadge"
              class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2 animate-scale-in"
            />
          </div>
        </component>
        <SidebarCollapsedPopover
          v-if="hasChildren && isPopoverOpen"
          :label="label"
          :children="children"
          :active-child="activeChild"
          :trigger-rect="triggerRect"
          @close="closePopover"
          @mouseenter="handlePopoverMouseEnter"
          @mouseleave="handlePopoverMouseLeave"
          @sort-toggle="handleSortToggle"
        />
      </div>
    </template>
    <!-- Expanded State -->
    <template v-else>
      <SidebarGroupHeader
        :icon
        :name
        :label
        :to
        :getter-keys="getterKeys"
        :is-active="isActive"
        :has-active-child="hasActiveChild"
        :expandable="hasChildren"
        :is-expanded="isExpanded"
        @toggle="toggleTrigger"
      />
      <ul
        v-if="hasChildren"
        v-show="isExpanded || hasActiveChild"
        class="grid m-0 list-none min-w-0"
      >
        <template v-for="child in visibleChildren" :key="child.name">
          <SidebarSubGroup
            v-if="child.children"
            :name="`${name}:${child.name}`"
            :label="child.label"
            :icon="child.icon"
            :children="child.children"
            :collapsible="child.collapsible"
            :show-tree-line="child.showTreeLine"
            :end-tree-line="child.showTreeLine && isLastVisibleChild(child)"
            :is-expanded="isExpanded"
            :active-child="activeChild"
            :sort-options="child.sortOptions"
            :active-sort="child.activeSort"
            @update-sort="child.onSortChange"
          />
          <SidebarGroupLeaf
            v-else-if="isAllowed(child.to)"
            v-show="isExpanded || activeChild?.name === child.name"
            v-bind="child"
            :active="activeChild?.name === child.name"
          />
        </template>
      </ul>
      <ul v-else-if="isExpandable && isExpanded">
        <SidebarGroupEmptyLeaf />
      </ul>
    </template>
  </Policy>
</template>
