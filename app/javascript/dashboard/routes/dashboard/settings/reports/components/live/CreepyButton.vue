<script setup>
import { ref, computed } from 'vue';

defineProps({
  active: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['click']);

const eyesRef = ref(null);
const buttonRef = ref(null);
const eyeCoords = ref({ x: 0, y: 0 });

const eyeStyle = computed(() => {
  const translateX = `${-50 + eyeCoords.value.x * 50}%`;
  const translateY = `${-50 + eyeCoords.value.y * 50}%`;
  return {
    transform: `translate(${translateX}, ${translateY})`,
  };
});

const updateEyes = e => {
  if (!eyesRef.value) {
    return;
  }

  const userEvent = e.touches ? e.touches[0] : e;
  const eyesRect = eyesRef.value.getBoundingClientRect();

  const eyes = {
    x: eyesRect.left + eyesRect.width / 2,
    y: eyesRect.top + eyesRect.height / 2,
  };

  const cursor = {
    x: userEvent.clientX,
    y: userEvent.clientY,
  };

  // Calcular o ângulo do olho
  const dx = cursor.x - eyes.x;
  const dy = cursor.y - eyes.y;
  const angle = Math.atan2(-dy, dx) + Math.PI / 2;

  // Distância da pupila do centro do olho
  const visionRangeX = 180;
  const visionRangeY = 75;
  const distance = Math.hypot(dx, dy);
  const x = (Math.sin(angle) * distance) / visionRangeX;
  const y = (Math.cos(angle) * distance) / visionRangeY;

  // Limitar movimento entre -1 e 1
  eyeCoords.value = {
    x: Math.max(-1, Math.min(1, x)),
    y: Math.max(-1, Math.min(1, y)),
  };
};

const handleClick = () => {
  emit('click');
};

const coverStyle = computed(() => ({
  transformOrigin: '1.25em 50%',
}));
</script>

<template>
  <button
    ref="buttonRef"
    type="button"
    class="creepy-btn relative cursor-pointer"
    :class="{
      'creepy-btn--active': active,
      'creepy-btn--inactive': !active,
    }"
    @click="handleClick"
    @mousemove="updateEyes"
    @touchmove.passive="updateEyes"
  >
    <span
      class="creepy-btn__cover relative z-10 block rounded-[inherit] text-sm font-medium text-white transition-all duration-300 ease-[cubic-bezier(0.65,0,0.35,1)]"
      :style="coverStyle"
    >
      <slot />
    </span>
    <span
      ref="eyesRef"
      class="creepy-btn__eyes absolute right-1 bottom-0.5 z-20 flex h-3 items-center gap-1.5 pointer-events-none opacity-0 transition-opacity duration-200"
    >
      <span
        class="creepy-btn__eye animate-eye-blink relative h-3 w-3 overflow-hidden rounded-full bg-white"
      >
        <span
          class="creepy-btn__pupil absolute top-1/2 left-1/2 h-1.5 w-1.5 rounded-full bg-n-teal-9"
          :style="eyeStyle"
        />
      </span>
      <span
        class="creepy-btn__eye animate-eye-blink relative h-3 w-3 overflow-hidden rounded-full bg-white"
      >
        <span
          class="creepy-btn__pupil absolute top-1/2 left-1/2 h-1.5 w-1.5 rounded-full bg-n-teal-9"
          :style="eyeStyle"
        />
      </span>
    </span>
  </button>
</template>

<style scoped>
.creepy-btn {
  background-color: #000;
  border: 0;
  border-radius: 1.25em;
  min-width: 9em;
  position: relative;
  padding: 0;
  outline: 0.1875em solid transparent;
  transition: outline 0.1s linear;
  -webkit-tap-highlight-color: transparent;
}

.creepy-btn:focus-visible {
  outline: 0.1875em solid hsl(173 80% 60%);
}

.creepy-btn__cover {
  border-radius: inherit;
  inset: 0;
  position: relative;
  display: block;
  box-shadow: 0 0 0 0.125em rgba(0, 0, 0, 1) inset;
  padding: 0.5em 1em;
  overflow: hidden;
}

/* Fundo do rótulo.
   O rótulo é branco fixo (`text-white`), então o fundo tem de ser um tom
   SÓLIDO. Antes vinha de `bg-n-teal-5` / `bg-n-slate-5` — mas o passo 5 da
   escala é "realce sutil", não cor de botão, e no tema claro o par ficava
   ilegível:
     branco sobre #d9dbdf (slate-5 claro, "Ativar Tempo Real")   = 1.39:1
     branco sobre #99ded1 (teal-5 claro, "Desativar Tempo Real") = 1.53:1
   No tema escuro os mesmos tokens já passavam (11.92:1 e 5.30:1), então o
   `.dark` preserva exatamente os valores antigos e só o claro muda:
     branco sobre #006c55 = 6.41:1   (ativo)
     branco sobre #54656f = 6.06:1   (inativo) */
.creepy-btn--active .creepy-btn__cover {
  background-color: #006c55;
}

.creepy-btn--inactive .creepy-btn__cover {
  background-color: #54656f;
}

.dark .creepy-btn--active .creepy-btn__cover {
  background-color: #007a63;
}

.dark .creepy-btn--inactive .creepy-btn__cover {
  background-color: #2a3942;
}

.creepy-btn:hover .creepy-btn__cover {
  transform: rotate(-12deg);
  transition-timing-function: cubic-bezier(0.65, 0, 0.35, 1.65);
}

/* O hover também estava ilegível, nos dois temas: `hsl(173 80% 40%)` é
   #14b8a5 e o branco em cima dava 2.49:1. Escurecido para 8.31:1, mantendo o
   mesmo gesto de "afunda ao passar o mouse" do estado inativo (que já estava
   ok em 7.47:1 e por isso continua intocado). */
.creepy-btn--active:hover .creepy-btn__cover {
  background-color: #00594a;
}

.creepy-btn--inactive:hover .creepy-btn__cover {
  background-color: hsl(215 20% 35%);
}

.creepy-btn:active .creepy-btn__cover {
  transform: rotate(0);
  transition-timing-function: cubic-bezier(0.65, 0, 0.35, 1);
}

.creepy-btn:active {
  transform: none;
}

.creepy-btn:hover .creepy-btn__eyes {
  opacity: 1;
}

.creepy-btn__pupil {
  transform: translate(-50%, -50%);
  transition: transform 0.15s ease-out;
}

@keyframes eye-blink {
  0%,
  92%,
  100% {
    animation-timing-function: cubic-bezier(0.32, 0, 0.67, 0);
    height: 0.75rem;
  }

  96% {
    animation-timing-function: cubic-bezier(0.33, 1, 0.68, 1);
    height: 0;
  }
}

.animate-eye-blink {
  animation: eye-blink 3s infinite;
}
</style>
