<script>
// Um áudio por vez na tela: dar play num pausa o que estava tocando.
let activeAudio = null;
</script>

<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  src: { type: String, required: true },
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

const formatTime = seconds => {
  if (!Number.isFinite(seconds)) return '--:--';
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
};

const timeLabel = computed(() =>
  current.value > 0
    ? `${formatTime(current.value)} / ${formatTime(duration.value)}`
    : formatTime(duration.value)
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
  status.value = 'loading';
  audio.play().catch(() => {
    status.value = 'error';
  });
};

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
  <div class="flex items-center gap-2 w-60 max-w-full">
    <audio
      ref="audioRef"
      :src="src"
      preload="metadata"
      class="hidden"
      @loadedmetadata="onLoadedMetadata"
      @durationchange="onDurationChange"
      @timeupdate="onTimeUpdate"
      @waiting="status = 'loading'"
      @playing="status = 'playing'"
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
        class="inline-flex items-center justify-center flex-shrink-0 w-8 h-8 transition-colors rounded-full bg-n-alpha-2 hover:bg-n-alpha-3"
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
      </button>
      <div class="flex flex-col flex-1 min-w-0 gap-0.5">
        <input
          type="range"
          min="0"
          step="0.1"
          :max="duration || 0"
          :value="current"
          :disabled="!duration"
          :title="t('INTERNAL_CHAT.AUDIO.SEEK')"
          :aria-label="t('INTERNAL_CHAT.AUDIO.SEEK')"
          class="w-full h-1 cursor-pointer accent-n-brand disabled:cursor-default"
          @input="seek"
        />
        <span class="text-[11px] leading-none tabular-nums opacity-75">
          {{ timeLabel }}
        </span>
      </div>
    </template>
  </div>
</template>
