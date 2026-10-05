<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import AudioPlayer from './AudioPlayer.vue';

// Grava, deixa ouvir e só então envia (ou descarta). Monta já gravando.
const emit = defineEmits(['send', 'cancel']);

const { t } = useI18n();

// Grava no formato nativo do navegador (webm/opus no Chrome, Edge e Firefox;
// mp4 no Safari), sem converter para MP3: a conversão rodava na própria aba e a
// travava ~3 s a cada minuto de áudio, e o arquivo saía 4x maior.
const MIME_TYPES = [
  'audio/webm;codecs=opus',
  'audio/mp4',
  'audio/ogg;codecs=opus',
];
const EXTENSIONS = {
  'audio/webm': 'webm',
  'audio/mp4': 'm4a',
  'audio/ogg': 'ogg',
};

// starting (pedindo o microfone) | recording | review (ouvir antes de enviar)
const phase = ref('starting');
const elapsed = ref(0);
const file = ref(null);
const previewUrl = ref('');

let stream = null;
let recorder = null;
let timer = null;
let disposed = false;

const elapsedLabel = computed(
  () =>
    `${Math.floor(elapsed.value / 60)}:${String(elapsed.value % 60).padStart(2, '0')}`
);

const stopStream = () => {
  clearInterval(timer);
  stream?.getTracks().forEach(track => track.stop());
};

const fail = message => {
  stopStream();
  useAlert(message);
  emit('cancel');
};

const micErrorMessage = name =>
  ({
    NotAllowedError: t('INTERNAL_CHAT.AUDIO.PERMISSION_DENIED'),
    NotFoundError: t('INTERNAL_CHAT.AUDIO.NO_MIC'),
  })[name] || t('INTERNAL_CHAT.AUDIO.RECORD_ERROR');

const start = async () => {
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    fail(t('INTERNAL_CHAT.AUDIO.UNSUPPORTED'));
    return;
  }
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch (error) {
    fail(micErrorMessage(error.name));
    return;
  }
  if (disposed) {
    stopStream();
    return;
  }
  const mimeType = MIME_TYPES.find(type => MediaRecorder.isTypeSupported(type));
  const chunks = [];
  recorder = new MediaRecorder(stream, { mimeType, audioBitsPerSecond: 32000 });
  recorder.ondataavailable = event => chunks.push(event.data);
  recorder.onstop = () => {
    const type = recorder.mimeType.split(';')[0];
    const name = `audio-${format(new Date(), 'yyyy-MM-dd-HHmm')}.${EXTENSIONS[type] || 'webm'}`;
    file.value = new File(chunks, name, { type });
    previewUrl.value = URL.createObjectURL(file.value);
    phase.value = 'review';
  };
  recorder.start();
  const startedAt = Date.now();
  timer = setInterval(() => {
    elapsed.value = Math.floor((Date.now() - startedAt) / 1000);
  }, 250);
  phase.value = 'recording';
};

const stop = () => {
  stopStream();
  recorder.stop();
};

onMounted(start);

onBeforeUnmount(() => {
  disposed = true;
  if (recorder?.state === 'recording') {
    recorder.onstop = null;
    recorder.stop();
  }
  stopStream();
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
});
</script>

<template>
  <div
    class="relative z-20 flex items-center gap-2 px-2 py-1 border shadow-sm rounded-3xl bg-wa-composer-input border-n-weak"
  >
    <button
      type="button"
      class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full w-9 h-9 text-n-ruby-11 hover:bg-n-alpha-2"
      :title="t('INTERNAL_CHAT.AUDIO.DISCARD')"
      :aria-label="t('INTERNAL_CHAT.AUDIO.DISCARD')"
      @click="emit('cancel')"
    >
      <span class="text-lg i-lucide-trash-2" />
    </button>

    <div class="flex items-center flex-1 min-w-0 gap-2 text-sm">
      <template v-if="phase === 'starting'">
        <span
          class="flex-shrink-0 i-lucide-loader-circle animate-spin text-n-slate-10"
        />
        <span class="truncate text-n-slate-11">
          {{ t('INTERNAL_CHAT.AUDIO.REQUESTING') }}
        </span>
      </template>
      <template v-else-if="phase === 'recording'">
        <span
          class="flex-shrink-0 rounded-full size-2.5 bg-n-ruby-9 animate-pulse"
        />
        <span class="font-medium text-n-slate-12">
          {{ t('INTERNAL_CHAT.AUDIO.RECORDING') }}
        </span>
        <span class="tabular-nums text-n-slate-11">{{ elapsedLabel }}</span>
      </template>
      <template v-else>
        <AudioPlayer :src="previewUrl" fluid class="text-n-slate-12" />
        <span class="flex-shrink-0 hidden text-xs md:inline text-n-slate-10">
          {{ t('INTERNAL_CHAT.AUDIO.REVIEW_HINT') }}
        </span>
      </template>
    </div>

    <button
      v-if="phase === 'recording'"
      type="button"
      class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 transition-all rounded-full shadow-sm bg-wa-composer-send text-wa-composer-send-fg hover:brightness-110"
      :title="t('INTERNAL_CHAT.AUDIO.STOP')"
      :aria-label="t('INTERNAL_CHAT.AUDIO.STOP')"
      @click="stop"
    >
      <span class="text-lg i-lucide-square" />
    </button>
    <button
      v-else-if="phase === 'review'"
      type="button"
      class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 transition-all rounded-full shadow-sm bg-wa-composer-send text-wa-composer-send-fg hover:brightness-110"
      :title="t('INTERNAL_CHAT.AUDIO.SEND')"
      :aria-label="t('INTERNAL_CHAT.AUDIO.SEND')"
      @click="emit('send', file)"
    >
      <span class="text-lg i-lucide-send-horizontal" />
    </button>
  </div>
</template>
