<script setup>
import { shallowRef, watch } from 'vue';

const props = defineProps({
  name: { type: String, required: true },
  size: { type: Number, default: 16 },
});

const modules = import.meta.glob('./*Icon.vue');
const comp = shallowRef(null);
const loaded = shallowRef(false);

watch(
  () => props.name,
  async n => {
    if (!n) {
      comp.value = null;
      loaded.value = false;
      return;
    }
    const pascal = n
      .split('-')
      .map(p => p.charAt(0).toUpperCase() + p.slice(1))
      .join('');
    const key = `./${pascal}Icon.vue`;
    const loader = modules[key];
    if (loader) {
      try {
        const mod = await loader();
        comp.value = mod.default;
        loaded.value = true;
      } catch {
        comp.value = null;
        loaded.value = false;
      }
    } else {
      comp.value = null;
      loaded.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <component
    :is="comp"
    v-if="loaded && comp"
    :size="size"
    v-bind="$attrs"
  />
  <span
    v-else
    :class="`i-lucide-${name}`"
    :style="{ width: `${size}px`, height: `${size}px` }"
    v-bind="$attrs"
  />
</template>
