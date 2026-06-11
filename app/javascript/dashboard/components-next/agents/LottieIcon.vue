<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue';
import lottie from 'lottie-web';

const props = defineProps({
  animationData: { type: Object, required: true },
  size: { type: Number, default: 24 },
  mode: { type: String, default: 'hover' },
  speed: { type: Number, default: 1 },
});

const container = ref(null);
let anim = null;
let direction = 1;

function initAnimation() {
  if (!container.value) return;
  if (anim) {
    anim.destroy();
    anim = null;
  }

  const isLoop = props.mode === 'loop';

  anim = lottie.loadAnimation({
    container: container.value,
    renderer: 'svg',
    loop: isLoop,
    autoplay: isLoop,
    animationData: JSON.parse(JSON.stringify(props.animationData)),
  });

  anim.setSpeed(props.speed);

  if (!isLoop) {
    // Começa parado no frame 0 (mostra o ícone estático)
    anim.goToAndStop(0, true);
    // Quando a animação completar, volta ao frame 0 (não fica "preso" no último frame)
    anim.addEventListener('complete', () => {
      if (anim) anim.goToAndStop(0, true);
    });
  }
}

function playOnce() {
  if (!anim || props.mode === 'loop') return;
  anim.setDirection(1);
  anim.goToAndPlay(0, true);
}

function handleMouseEnter() {
  if (props.mode === 'hover') playOnce();
}

function handleClick() {
  if (!anim) return;
  if (props.mode === 'click') {
    playOnce();
  } else if (props.mode === 'reverseClick') {
    direction = direction === 1 ? -1 : 1;
    anim.setDirection(direction);
    anim.play();
  }
}

onMounted(() => {
  nextTick(initAnimation);
});

watch(
  () => props.animationData,
  () => {
    nextTick(initAnimation);
  }
);

onUnmounted(() => {
  if (anim) {
    anim.destroy();
    anim = null;
  }
});

defineExpose({ playOnce });
</script>

<template>
  <div
    ref="container"
    class="inline-flex shrink-0 items-center justify-center dark:invert"
    :style="{ width: `${size}px`, height: `${size}px` }"
    @mouseenter="handleMouseEnter"
    @click="handleClick"
  />
</template>
