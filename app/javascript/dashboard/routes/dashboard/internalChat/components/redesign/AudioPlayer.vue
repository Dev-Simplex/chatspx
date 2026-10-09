<script>
// Um áudio por vez na tela: dar play num pausa o que estava tocando.
let activeAudio = null;

// Velocidade escolhida e áudios já ouvidos ficam no navegador (localStorage
// pode faltar: aba anônima — aí só não lembra).
const RATE_KEY = 'internal_chat_audio_rate';
const HEARD_KEY = 'internal_chat_audio_heard';
const RATES = [1, 1.5, 2];
const HEARD_LIMIT = 500;
const readStored = (key, fallback) => {
  try {
    return JSON.parse(localStorage.getItem(key)) ?? fallback;
  } catch (e) {
    return fallback;
  }
};
const store = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch (e) {
    // sem armazenamento
  }
};
const storedRate = () => {
  const rate = Number(readStored(RATE_KEY, 1));
  return RATES.includes(rate) ? rate : 1;
};
</script>

<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  src: { type: String, required: true },
  // Ocupa a largura que sobrar (prévia no composer) em vez da largura fixa do balão.
  fluid: { type: Boolean, default: false },
  // Áudio recebido: mostra o ponto de "ainda não ouvido" até dar play.
  heardKey: { type: [String, Number], default: null },
});

const { t } = useI18n();

const audioRef = ref(null);
// idle | loading | playing | paused | error
const status = ref('idle');
const duration = ref(0);
const current = ref(0);
// Arquivo sem duração no cabeçalho (webm gravado no navegador): pular para o
// fim força o navegador a calcular a duração; depois volta para o início.
const fixingDuration = ref(false);

// ── Velocidade 1× / 1,5× / 2× ────────────────────────────────────────────
const rate = ref(storedRate());
const rateLabel = computed(() => `${String(rate.value).replace('.', ',')}×`);
const cycleRate = () => {
  const next = RATES[(RATES.indexOf(rate.value) + 1) % RATES.length];
  rate.value = next;
  store(RATE_KEY, next);
  if (audioRef.value) audioRef.value.playbackRate = next;
};

// ── Ouvido / não ouvido ──────────────────────────────────────────────────
const heard = ref(
  props.heardKey == null ||
    readStored(HEARD_KEY, []).includes(String(props.heardKey))
);
const markHeard = () => {
  if (heard.value) return;
  heard.value = true;
  const list = readStored(HEARD_KEY, []).filter(
    k => k !== String(props.heardKey)
  );
  store(HEARD_KEY, [...list, String(props.heardKey)].slice(-HEARD_LIMIT));
};
const onPlaying = () => {
  status.value = 'playing';
  markHeard();
};

const formatTime = seconds => {
  if (!Number.isFinite(seconds)) return '--:--';
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
};

// Sempre "atual / total": o texto não muda de largura ao dar play e a barra não pula.
const timeLabel = computed(
  () => `${formatTime(current.value)} / ${formatTime(duration.value)}`
);

// Os handlers leem o elemento do evento: o pause() do unmount ainda dispara
// timeupdate depois que o ref já foi limpo.
const onLoadedMetadata = ({ target: audio }) => {
  if (Number.isFinite(audio.duration)) {
    duration.value = audio.duration;
    return;
  }
  fixingDuration.value = true;
  audio.currentTime = 1e101;
};

const onDurationChange = ({ target: audio }) => {
  if (!fixingDuration.value || !Number.isFinite(audio.duration)) return;
  duration.value = audio.duration;
  fixingDuration.value = false;
  audio.currentTime = 0;
};

const onTimeUpdate = ({ target: audio }) => {
  if (!fixingDuration.value) current.value = audio.currentTime;
};

const onEnded = () => {
  status.value = 'idle';
  current.value = 0;
};

const toggle = () => {
  const audio = audioRef.value;
  if (status.value === 'playing') {
    audio.pause();
    return;
  }
  if (activeAudio && activeAudio !== audio) activeAudio.pause();
  activeAudio = audio;
  // A velocidade pode ter mudado em outro áudio desde o último play.
  rate.value = storedRate();
  audio.playbackRate = rate.value;
  status.value = 'loading';
  audio.play().catch(() => {
    status.value = 'error';
  });
};

const progress = computed(() =>
  duration.value ? Math.min(100, (current.value / duration.value) * 100) : 0
);

const seek = event => {
  audioRef.value.currentTime = Number(event.target.value);
};

// Sair da tela (ou descartar a prévia) com o áudio tocando: para o som.
onBeforeUnmount(() => {
  audioRef.value.pause();
  if (activeAudio === audioRef.value) activeAudio = null;
});
</script>

<template>
  <div
    class="flex items-center gap-3 max-w-full"
    :class="fluid ? 'flex-1 min-w-0' : 'w-72'"
  >
    <audio
      ref="audioRef"
      :src="src"
      preload="metadata"
      class="hidden"
      @loadedmetadata="onLoadedMetadata"
      @durationchange="onDurationChange"
      @timeupdate="onTimeUpdate"
      @waiting="status = 'loading'"
      @playing="onPlaying"
      @pause="status = status === 'error' ? 'error' : 'paused'"
      @ended="onEnded"
      @error="status = 'error'"
    />

    <template v-if="status === 'error'">
      <span class="flex-shrink-0 i-lucide-circle-alert text-n-ruby-11" />
      <span class="flex-1 min-w-0 text-xs">
        {{ t('INTERNAL_CHAT.AUDIO.PLAY_ERROR') }}
        <a :href="src" download class="font-medium underline">
          {{ t('INTERNAL_CHAT.AUDIO.DOWNLOAD') }}
        </a>
      </span>
    </template>

    <template v-else>
      <button
        type="button"
        class="relative inline-flex items-center justify-center flex-shrink-0 w-8 h-8 transition-colors rounded-full bg-[color-mix(in_srgb,currentColor_14%,transparent)] hover:bg-[color-mix(in_srgb,currentColor_24%,transparent)]"
        :title="
          status === 'playing'
            ? t('INTERNAL_CHAT.AUDIO.PAUSE')
            : t('INTERNAL_CHAT.AUDIO.PLAY')
        "
        :aria-label="
          status === 'playing'
            ? t('INTERNAL_CHAT.AUDIO.PAUSE')
            : t('INTERNAL_CHAT.AUDIO.PLAY')
        "
        @click="toggle"
      >
        <span
          v-if="status === 'loading'"
          class="i-lucide-loader-circle animate-spin"
        />
        <span v-else-if="status === 'playing'" class="i-lucide-pause" />
        <span v-else class="i-lucide-play" />
        <!-- Ainda não ouvido (áudio recebido): ponto no play, como no WhatsApp -->
        <span
          v-if="!heard"
          v-tooltip="t('INTERNAL_CHAT.AUDIO.NOT_HEARD')"
          class="absolute -top-0.5 -right-0.5 rounded-full size-2.5 bg-n-teal-9"
          :aria-label="t('INTERNAL_CHAT.AUDIO.NOT_HEARD')"
          role="img"
        />
      </button>
      <!-- Velocidade perto do play: o canto direito do balão é do menu ⌄ -->
      <button
        v-tooltip="t('INTERNAL_CHAT.AUDIO.SPEED', { rate: rateLabel })"
        type="button"
        class="flex-shrink-0 h-6 px-1.5 text-[11px] font-bold tabular-nums rounded-full transition-colors bg-[color-mix(in_srgb,currentColor_14%,transparent)] hover:bg-[color-mix(in_srgb,currentColor_24%,transparent)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-current"
        :aria-label="t('INTERNAL_CHAT.AUDIO.SPEED', { rate: rateLabel })"
        @click="cycleRate"
      >
        {{ rateLabel }}
      </button>
      <div class="relative flex items-center flex-1 h-6 min-w-0 group">
        <!-- trilha na cor do texto: lê no balão verde e no cinza -->
        <div
          class="w-full h-1.5 rounded-full bg-[color-mix(in_srgb,currentColor_22%,transparent)]"
        >
          <div
            class="h-full rounded-full bg-current"
            :style="{ width: `${progress}%` }"
          />
        </div>
        <span
          v-if="duration"
          class="absolute -translate-x-1/2 rounded-full shadow pointer-events-none size-3 bg-current ring-2 ring-n-solid-1"
          :style="{ left: `${progress}%` }"
        />
        <input
          type="range"
          min="0"
          step="0.1"
          :max="duration || 0"
          :value="current"
          :disabled="!duration"
          :title="t('INTERNAL_CHAT.AUDIO.SEEK')"
          :aria-label="t('INTERNAL_CHAT.AUDIO.SEEK')"
          class="absolute inset-0 w-full h-full opacity-0 cursor-pointer disabled:cursor-default"
          @input="seek"
        />
      </div>
      <span class="flex-shrink-0 text-xs tabular-nums opacity-75">
        {{ timeLabel }}
      </span>
    </template>
  </div>
</template>
