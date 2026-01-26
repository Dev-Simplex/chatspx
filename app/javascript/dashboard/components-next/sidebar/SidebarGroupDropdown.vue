<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useSidebarContext } from './provider';
import {
  DropdownContainer,
  DropdownBody,
  DropdownItem,
} from 'next/dropdown-menu/base';
import Icon from 'next/icon/Icon.vue';
import Policy from 'dashboard/components/policy.vue';

const props = defineProps({
  children: { type: Array, required: true },
  activeChild: { type: Object, default: undefined },
  label: { type: String, required: true },
  icon: { type: [String, Object], default: null },
});

const router = useRouter();
const { resolvePath, resolvePermissions, resolveFeatureFlag, isAllowed } =
  useSidebarContext();

const accessibleItems = computed(() => {
  if (!props.children || props.children.length === 0) return [];

  return props.children.filter(child => {
    // Se tem children, verificar se tem pelo menos um filho acessível
    if (child.children && Array.isArray(child.children)) {
      const hasAccessibleChild = child.children.some(
        subChild => subChild.to && isAllowed(subChild.to)
      );
      return hasAccessibleChild;
    }
    // Se não tem children, verificar se tem to e é permitido
    return child.to && isAllowed(child.to);
  });
});

const directItems = computed(() => {
  return accessibleItems.value.filter(child => !child.children);
});

const subgroupItems = computed(() => {
  return accessibleItems.value.filter(
    child => child.children && Array.isArray(child.children)
  );
});

const isChildActive = child => {
  if (!child.to) return false;
  const childPath = resolvePath(child.to);
  return router.currentRoute.value.path === childPath;
};
</script>

<template>
  <DropdownBody
    class="min-w-56 z-[100] ltr:left-full rtl:right-full ltr:ml-2 rtl:mr-2 top-0 ltr:origin-left rtl:origin-right"
  >
    <!-- Itens diretos sem children -->
    <Policy
      v-for="child in directItems"
      :key="child.name"
      :permissions="child.to ? resolvePermissions(child.to) : []"
      :feature-flag="child.to ? resolveFeatureFlag(child.to) : ''"
      as="template"
    >
      <DropdownItem
        :label="child.label"
        :icon="child.icon"
        :link="child.to"
        :class="{
          'bg-n-alpha-2 text-n-blue-text': isChildActive(child),
        }"
      />
    </Policy>
    <!-- Subgrupos com children -->
    <DropdownItem
      v-for="child in subgroupItems"
      :key="child.name"
      preserve-open
      :class="{
        'bg-n-alpha-2 text-n-blue-text': child.children.some(c =>
          isChildActive(c)
        ),
      }"
    >
      <div class="flex items-center gap-2 w-full">
        <Icon
          v-if="child.icon"
          :icon="child.icon"
          class="size-4 text-n-slate-11"
        />
        <span class="text-sm font-medium flex-grow">{{ child.label }}</span>
        <DropdownContainer>
          <template #trigger="{ toggle }">
            <Icon
              icon="i-lucide-chevron-right"
              class="size-4 text-n-slate-11 flex-shrink-0 cursor-pointer"
              @click.stop="toggle"
            />
          </template>
          <DropdownBody
            class="min-w-56 z-[110] ltr:left-full rtl:right-full ltr:ml-2 rtl:mr-2 top-0"
            strong
          >
            <Policy
              v-for="subChild in child.children.filter(
                c => c.to && isAllowed(c.to)
              )"
              :key="subChild.name"
              :permissions="resolvePermissions(subChild.to)"
              :feature-flag="resolveFeatureFlag(subChild.to)"
              as="template"
            >
              <DropdownItem
                :label="subChild.label"
                :icon="subChild.icon"
                :link="subChild.to"
                :class="{
                  'bg-n-alpha-2 text-n-blue-text': isChildActive(subChild),
                }"
              />
            </Policy>
          </DropdownBody>
        </DropdownContainer>
      </div>
    </DropdownItem>
  </DropdownBody>
</template>
