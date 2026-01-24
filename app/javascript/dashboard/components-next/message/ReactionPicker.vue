<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  position: {
    type: Object,
    default: () => ({ top: 0, left: 0 }),
  },
});

const emit = defineEmits(['select', 'close']);

// Emojis mais comuns estilo WhatsApp
const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];

const pickerRef = ref(null);

// Dimensões aproximadas do picker
const PICKER_WIDTH = 320; // 8 emojis * 40px + gaps
const PICKER_HEIGHT = 60;
const PADDING = 16;
const BUTTON_HEIGHT = 40; // altura aproximada do botão de reação

// Calcular posição ajustada para viewport
const adjustedPosition = computed(() => {
  if (!props.show) return { top: 0, left: 0 };

  // Obter dimensões da viewport visível (sem scrollbars)
  const viewportWidth = document.documentElement.clientWidth;
  const viewportHeight = document.documentElement.clientHeight;
  
  // Posição do botão relativa à viewport (já vem de getBoundingClientRect)
  let top = props.position.top;
  let left = props.position.left;

  // Ajustar horizontalmente - garantir que não saia da viewport
  if (left + PICKER_WIDTH > viewportWidth - PADDING) {
    // Não cabe à direita, alinhar à direita da viewport
    left = viewportWidth - PICKER_WIDTH - PADDING;
  }
  if (left < PADDING) {
    // Não cabe à esquerda, alinhar à esquerda
    left = PADDING;
  }

  // Ajustar verticalmente - preferir acima do botão
  const spaceAbove = top - PADDING;
  const spaceBelow = viewportHeight - top - BUTTON_HEIGHT - PADDING;
  
  if (spaceAbove >= PICKER_HEIGHT) {
    // Cabe acima, posicionar acima do botão
    top = top - PICKER_HEIGHT - 8;
  } else if (spaceBelow >= PICKER_HEIGHT) {
    // Não cabe acima, mas cabe abaixo
    top = top + BUTTON_HEIGHT + 8;
  } else {
    // Não cabe nem acima nem abaixo, centralizar verticalmente na viewport
    top = Math.max(PADDING, (viewportHeight - PICKER_HEIGHT) / 2);
  }

  // Garantir que não saia da viewport verticalmente (última verificação)
  if (top + PICKER_HEIGHT > viewportHeight - PADDING) {
    top = viewportHeight - PICKER_HEIGHT - PADDING;
  }
  if (top < PADDING) {
    top = PADDING;
  }

  // Garantir que não cause scroll horizontal
  if (left + PICKER_WIDTH > viewportWidth - PADDING) {
    left = viewportWidth - PICKER_WIDTH - PADDING;
  }

  return { top, left };
});

const handleEmojiSelect = (emoji) => {
  emit('select', emoji);
};

const handleClickOutside = (event) => {
  if (pickerRef.value && !pickerRef.value.contains(event.target)) {
    emit('close');
  }
};

watch(() => props.show, (newValue) => {
  if (newValue) {
    document.addEventListener('mousedown', handleClickOutside);
  } else {
    document.removeEventListener('mousedown', handleClickOutside);
  }
});

onUnmounted(() => {
  document.removeEventListener('mousedown', handleClickOutside);
});
</script>

<template>
  <Transition
    enter-active-class="transition ease-out duration-100"
    enter-from-class="transform opacity-0 scale-95"
    enter-to-class="transform opacity-100 scale-100"
    leave-active-class="transition ease-in duration-75"
    leave-from-class="transform opacity-100 scale-100"
    leave-to-class="transform opacity-0 scale-95"
  >
    <Teleport to="body">
      <div
        v-if="show"
        ref="pickerRef"
        :style="{
          top: `${adjustedPosition.top}px`,
          left: `${adjustedPosition.left}px`,
        }"
        class="fixed z-[9999] bg-white dark:bg-slate-800 rounded-lg shadow-lg border border-slate-200 dark:border-slate-700 p-2 pointer-events-auto"
        style="max-width: calc(100vw - 32px); max-height: calc(100vh - 32px);"
      >
      <div class="flex gap-1">
        <button
          v-for="emoji in quickReactions"
          :key="emoji"
          class="w-10 h-10 flex items-center justify-center text-2xl rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors duration-150 active:scale-90"
          @click="handleEmojiSelect(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
      </div>
    </Teleport>
  </Transition>
</template>

