<script setup>
import { computed, ref, onMounted } from 'vue';

const props = defineProps({
  assistant: { type: Object, default: () => ({}) },
});
// Timeline vertical em pt-BR, GERADA da config real do agente (não genérica).
// Animada: entrada em cascata + conectores com energia + "Reproduzir" (acende passo a passo).
defineOptions({ name: 'AgentFlowSimple' });
const LANE = 'O que o agente faz';
const REPLAY = 'Reproduzir';

const behavior = computed(() => props.assistant?.behavior || {});
const config = computed(() => props.assistant?.config || {});

const isOn = key => {
  const v = behavior.value[key];
  if (!v) return false;
  if (typeof v === 'object') return v.enabled !== false;
  return Boolean(v);
};

const steps = computed(() => {
  const bh = behavior.value;
  const cfg = config.value;
  const list = [];
  list.push({
    icon: 'i-lucide-message-square',
    color: '#0a84ff',
    title: 'Recebe a mensagem no WhatsApp',
    sub: 'Canal de atendimento',
  });
  if (isOn('business_hours')) {
    const tz = bh.business_hours?.timezone;
    list.push({
      icon: 'i-lucide-clock',
      color: '#af52de',
      title: 'Confere o horário de atendimento',
      sub: tz
        ? `${tz} · fora do horário, avisa e segura`
        : 'Fora do horário, avisa e segura',
    });
  }
  if (Number(bh.debounce_seconds) > 0) {
    list.push({
      icon: 'i-lucide-timer',
      color: '#30b0c7',
      title: 'Espera o cliente terminar de escrever',
      sub: `Agrupa mensagens por ${bh.debounce_seconds}s antes de responder`,
    });
  }
  if (isOn('media_pipeline')) {
    const mp = bh.media_pipeline || {};
    const feats = [
      mp.audio_transcription && 'áudios',
      mp.image_description && 'imagens',
    ]
      .filter(Boolean)
      .join(' e ');
    list.push({
      icon: 'i-lucide-image',
      color: '#5e5ce6',
      title: 'Processa mídias',
      sub: feats ? `Entende ${feats}` : 'Áudios e imagens',
    });
  }
  list.push({
    icon: 'i-lucide-bot',
    color: '#1faa59',
    title: 'Entende e responde',
    sub: cfg.model ? `Modelo: ${cfg.model}` : 'IA do agente',
  });
  if (isOn('dedup')) {
    list.push({
      icon: 'i-lucide-copy-slash',
      color: '#ff9500',
      title: 'Evita responder repetido',
      sub: bh.dedup?.ttl_seconds ? `Janela de ${bh.dedup.ttl_seconds}s` : '',
    });
  }
  if (isOn('humanizer')) {
    list.push({
      icon: 'i-lucide-pen-tool',
      color: '#ff2d55',
      title: 'Escreve como humano',
      sub: bh.humanizer?.max_chars
        ? `Até ${bh.humanizer.max_chars} caracteres por mensagem`
        : '',
    });
  }
  list.push({
    icon: 'i-lucide-send',
    color: '#34c759',
    title: 'Responde no WhatsApp',
    sub: '',
  });
  list.push({
    icon: 'i-lucide-user-check',
    color: '#ff3b30',
    title: 'Passa pra humano quando precisar',
    sub: 'Quando o cliente pede ou a IA não sabe responder',
    handoff: true,
  });
  return list;
});

const activeStep = ref(-1);
const prm =
  typeof matchMedia !== 'undefined' &&
  matchMedia('(prefers-reduced-motion: reduce)').matches;

function playFlow() {
  if (prm) return;
  activeStep.value = -1;
  const n = steps.value.length;
  steps.value.forEach((_, i) =>
    setTimeout(() => {
      activeStep.value = i;
    }, i * 420)
  );
  setTimeout(
    () => {
      activeStep.value = -1;
    },
    n * 420 + 700
  );
}

onMounted(() => setTimeout(playFlow, 400));
</script>

<template>
  <div class="px-1">
    <div class="flex justify-between items-center px-1 pb-3">
      <p class="text-xs font-bold tracking-wide uppercase text-n-slate-10">
        {{ LANE }}
      </p>
      <button
        type="button"
        class="inline-flex gap-1.5 items-center px-3 py-1.5 text-[12px] font-semibold rounded-lg border transition border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2 active:scale-95"
        @click="playFlow"
      >
        <span class="i-lucide-play size-3.5" />
        {{ REPLAY }}
      </button>
    </div>
    <div
      v-for="(s, i) in steps"
      :key="i"
      class="flex gap-3.5 step"
      :class="{ 'is-lit': i === activeStep }"
      :style="{ animationDelay: `${i * 60}ms` }"
    >
      <div class="flex flex-col flex-none items-center">
        <span
          class="grid place-items-center text-white rounded-[11px] shadow-sm transition-transform duration-300 node size-9"
          :style="{ background: s.color }"
        >
          <span :class="s.icon" class="size-[18px]" />
        </span>
        <span
          v-if="i < steps.length - 1"
          class="flex-1 my-1 w-0.5 conn bg-n-weak"
        />
      </div>
      <div class="flex-1 pb-3.5">
        <div
          class="p-3 rounded-2xl border shadow-sm"
          :class="
            s.handoff
              ? 'border-n-ruby-6 bg-n-ruby-2 dark:bg-n-ruby-3'
              : 'border-n-weak bg-n-solid-1'
          "
        >
          <p class="text-[14px] font-bold text-n-slate-12">{{ s.title }}</p>
          <p v-if="s.sub" class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ s.sub }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.step {
  animation: fs-rise 0.45s cubic-bezier(0.22, 1, 0.36, 1) both;
}
@keyframes fs-rise {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
.node {
  will-change: transform;
}
.is-lit .node {
  transform: scale(1.16);
  box-shadow: 0 0 0 6px rgba(31, 170, 89, 0.18);
}
.conn {
  position: relative;
  overflow: visible;
}
.conn::after {
  content: '';
  position: absolute;
  left: -2px;
  top: 0;
  width: 6px;
  height: 6px;
  border-radius: 9999px;
  background: #1faa59;
  box-shadow: 0 0 8px rgba(31, 170, 89, 0.6);
  animation: fs-drop 2.4s linear infinite;
}
@keyframes fs-drop {
  0% {
    top: -6px;
    opacity: 0;
  }
  12% {
    opacity: 1;
  }
  88% {
    opacity: 1;
  }
  100% {
    top: 100%;
    opacity: 0;
  }
}
@media (prefers-reduced-motion: reduce) {
  .step {
    animation: none;
  }
  .conn::after {
    display: none;
  }
  .is-lit .node {
    box-shadow: none;
    transform: none;
  }
}
</style>
