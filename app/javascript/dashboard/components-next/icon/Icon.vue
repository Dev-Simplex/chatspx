<script setup>
import { h, isVNode, shallowRef, watch } from 'vue';

const props = defineProps({
  icon: { type: [String, Object, Function], required: true },
});

// Vite glob import for all animated icons
const animatedModules = import.meta.glob('../animated-icons/*Icon.vue');

const animatedComp = shallowRef(null);

watch(
  () =>
    typeof props.icon === 'string' && props.icon.startsWith('i-lucide-')
      ? props.icon
      : null,
  async iconClass => {
    if (!iconClass) {
      animatedComp.value = null;
      return;
    }
    const name = iconClass
      .replace('i-lucide-', '')
      .split('-')
      .map(p => p.charAt(0).toUpperCase() + p.slice(1))
      .join('');

    const key = `../animated-icons/${name}Icon.vue`;
    const loader = animatedModules[key];

    if (loader) {
      try {
        const mod = await loader();
        animatedComp.value = mod.default;
      } catch {
        animatedComp.value = null;
      }
    } else {
      animatedComp.value = null;
    }
  },
  { immediate: true }
);

const renderIcon = () => {
  if (!props.icon) return null;
  if (typeof props.icon === 'function' || isVNode(props.icon)) {
    return props.icon;
  }
  // Use animated SVG component if loaded
  if (animatedComp.value) {
    return h(animatedComp.value, { size: 16 });
  }
  // Fallback to static span
  return h('span', { class: props.icon });
};
</script>

<template>
  <component :is="renderIcon" />
</template>
