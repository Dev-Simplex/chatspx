<script setup>
import { ref } from 'vue';
import { useIntersectionObserver } from '@vueuse/core';

const props = defineProps({
  src: { type: String, required: true },
  alt: { type: String, default: '' },
  width: { type: [Number, String], default: 400 },
  height: { type: [Number, String], default: 400 },
  eager: { type: Boolean, default: false },
  highPriority: { type: Boolean, default: false },
});

const target = ref(null);
const inView = ref(props.eager);
const loaded = ref(false);
const errored = ref(false);

if (!props.eager) {
  const { stop } = useIntersectionObserver(
    target,
    ([{ isIntersecting }]) => {
      if (isIntersecting) {
        inView.value = true;
        stop();
      }
    },
    { rootMargin: '200px' }
  );
}

const onLoad = () => {
  loaded.value = true;
};

const onError = () => {
  errored.value = true;
};
</script>

<template>
  <div ref="target" class="absolute inset-0 w-full h-full">
    <img
      v-if="inView && !errored"
      :src="src"
      :width="width"
      :height="height"
      :alt="alt"
      :loading="eager ? 'eager' : 'lazy'"
      :fetchpriority="highPriority ? 'high' : 'low'"
      decoding="async"
      class="w-full h-full object-cover transition-all duration-300 group-hover:scale-105"
      :class="loaded ? 'opacity-100' : 'opacity-0'"
      @load="onLoad"
      @error="onError"
    />
    <div
      v-if="!loaded && !errored"
      class="absolute inset-0 bg-n-slate-3 animate-pulse motion-reduce:animate-none"
      aria-hidden="true"
    />
    <div
      v-if="errored"
      class="absolute inset-0 flex items-center justify-center bg-n-slate-3 text-n-slate-10"
      aria-hidden="true"
    >
      <span class="i-lucide-image-off size-8" />
    </div>
  </div>
</template>
