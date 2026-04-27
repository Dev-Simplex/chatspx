<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  /** URL do JSON idle (outline) */
  src: { type: String, required: true },
  /** URL do JSON solid — se presente e active=true, troca pra essa no ativo */
  srcActive: { type: String, default: '' },
  /** Família: 'system' (tem solid variant) ou 'wired' (sem solid, só cor+stroke) */
  family: { type: String, default: 'system' },
  /** Se true, força ativo. Se false, detecta via ancestor [data-sidebar-active="true"] */
  active: { type: Boolean, default: false },
  /** Tamanho em px */
  size: { type: Number, default: 22 },
  /** Lordicon stroke idle: 'light' | 'regular' | 'bold' */
  stroke: { type: String, default: 'bold' },
  /** Seletor do ancestor que dispara animação ao receber mouseenter */
  hoverHostSelector: { type: String, default: '[data-hover-host]' },
  /** Classe Lucide exibida como fallback até o Lordicon carregar */
  fallbackLucide: { type: String, default: '' },
});

// active detectado: prop OR ancestor com data-sidebar-active="true"
const ancestorActive = ref(false);
const isActive = computed(() => props.active || ancestorActive.value);

const wrapperRef = ref(null);
const iconRef = ref(null);
const loaded = ref(false);

const isDarkMode = ref(
  typeof document !== 'undefined' && document.body?.classList.contains('dark')
);

let themeObserver = null;

// Cor ativa: verde brand ChatSPX (#2dc46f — match com logo)
const ACTIVE_COLOR = '#2dc46f';

const colors = computed(() => {
  if (isActive.value)
    return `primary:${ACTIVE_COLOR},secondary:${ACTIVE_COLOR}`;
  const idle = isDarkMode.value ? '#aebac1' : '#54656f';
  return `primary:${idle},secondary:${idle}`;
});

// src real renderizado: se active+srcActive presente (System), usa solid
const currentSrc = computed(() => {
  if (isActive.value && props.srcActive) return props.srcActive;
  return props.src;
});

// Stroke dinâmico: Wired fallback fica bold no ativo pra compensar falta de filled
const currentStroke = computed(() => {
  if (props.family === 'wired' && isActive.value) return 'bold';
  return props.stroke;
});

const wrapperStyle = computed(() => ({
  width: `${props.size}px`,
  height: `${props.size}px`,
}));

const playerStyle = computed(() => ({ opacity: loaded.value ? 1 : 0 }));

let cleanup = () => {};

const playAnimation = () => {
  const iconEl = iconRef.value;
  if (!iconEl) return;
  const player = iconEl.playerInstance;
  if (player && typeof player.playFromBeginning === 'function') {
    player.playFromBeginning();
  }
};

let activeObserver = null;

const updateAncestorActive = () => {
  const el = wrapperRef.value?.closest('[data-sidebar-active]');
  ancestorActive.value = el?.getAttribute('data-sidebar-active') === 'true';
};

onMounted(() => {
  const iconEl = iconRef.value;
  if (!iconEl) return;

  const onReady = () => {
    loaded.value = true;
    if (isActive.value) playAnimation();
  };
  iconEl.addEventListener('ready', onReady);

  const host = wrapperRef.value?.closest(props.hoverHostSelector);
  let onEnter = null;
  if (host) {
    onEnter = () => playAnimation();
    host.addEventListener('mouseenter', onEnter);
  }

  themeObserver = new MutationObserver(() => {
    isDarkMode.value = document.body.classList.contains('dark');
  });
  themeObserver.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });

  // Observa mudança do data-sidebar-active no ancestor
  updateAncestorActive();
  const ancestor = wrapperRef.value?.closest('[data-sidebar-active]');
  if (ancestor) {
    activeObserver = new MutationObserver(updateAncestorActive);
    activeObserver.observe(ancestor, {
      attributes: true,
      attributeFilter: ['data-sidebar-active'],
    });
  }

  const loadTimeout = setTimeout(() => {
    loaded.value = true;
  }, 3000);

  cleanup = () => {
    iconEl.removeEventListener('ready', onReady);
    if (host && onEnter) host.removeEventListener('mouseenter', onEnter);
    themeObserver?.disconnect();
    activeObserver?.disconnect();
    clearTimeout(loadTimeout);
  };
});

onBeforeUnmount(() => cleanup());

watch(isActive, val => {
  if (val && loaded.value) {
    playAnimation();
  }
});
</script>

<template>
  <span
    ref="wrapperRef"
    class="lord-icon-wrapper"
    :style="wrapperStyle"
    aria-hidden="true"
  >
    <span
      v-if="!loaded && fallbackLucide"
      :class="fallbackLucide"
      class="lord-icon-fallback"
    />
    <!-- eslint-disable-next-line vue/no-undef-components -->
    <lord-icon
      ref="iconRef"
      :src="currentSrc"
      :stroke="currentStroke"
      :colors="colors"
      class="lord-icon-player"
      :style="playerStyle"
    />
  </span>
</template>

<style scoped>
.lord-icon-wrapper {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  position: relative;
  flex-shrink: 0;
}
.lord-icon-fallback {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  color: currentColor;
}
.lord-icon-player {
  width: 100%;
  height: 100%;
  transition: opacity 0.2s;
}
</style>
