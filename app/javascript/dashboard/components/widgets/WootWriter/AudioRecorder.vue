<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted, defineEmits, defineExpose } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import * as Sentry from '@sentry/vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { convertAudio } from './utils/mp3ConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'pause',
  'play',
  'recordStart',
  'recordPause',
  'recordResume',
  'recordProcessing',
  'recordError',
]);

const { t } = useI18n();

const waveformContainer = ref(null);
const wavesurfer = ref(null);
const record = ref(null);
const isRecording = ref(false);
const isRecordingPaused = ref(false);
const isProcessing = ref(false);
const isPlaying = ref(false);
const hasRecording = ref(false);
const currentAudioUrl = ref(null);

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const initWaveSurfer = () => {
  wavesurfer.value = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create({
        scrollingWaveform: true,
        renderRecordedAudio: false,
      }),
    ],
  });

  wavesurfer.value.on('pause', () => emit('pause'));
  wavesurfer.value.on('play', () => emit('play'));

  record.value = wavesurfer.value.plugins[0];

  wavesurfer.value.on('finish', () => {
    isPlaying.value = false;
  });

  record.value.on('record-start', () => {
    isRecording.value = true;
    isRecordingPaused.value = false;
    emit('recordStart');
  });

  record.value.on('record-pause', () => {
    isRecording.value = false;
    isRecordingPaused.value = true;
    emit('recordPause');
  });

  record.value.on('record-resume', () => {
    isRecording.value = true;
    isRecordingPaused.value = false;
    emit('recordResume');
  });

  record.value.on('record-end', async blob => {
    isRecording.value = false;
    isRecordingPaused.value = false;
    isProcessing.value = true;
    emit('recordProcessing');

    try {
      if (currentAudioUrl.value) {
        URL.revokeObjectURL(currentAudioUrl.value);
      }
      const audioUrl = URL.createObjectURL(blob);
      currentAudioUrl.value = audioUrl;
      const audioBlob = await convertAudio(blob, props.audioRecordFormat);
      const fileName = `${getUuid()}.mp3`;
      const file = new File([audioBlob], fileName, {
        type: props.audioRecordFormat,
      });
      wavesurfer.value.load(audioUrl);
      emit('finishRecord', {
        name: file.name,
        type: file.type,
        size: file.size,
        file,
      });
      hasRecording.value = true;
    } catch (error) {
      // convertAudio (mp3/wav encoding) can throw on unsupported formats or a
      // decode failure. Previously this rejected silently inside the async
      // handler, leaving the agent staring at a stuck "processing" spinner.
      // Surface it: reset state, tell the user, notify the parent, log to Sentry.
      hasRecording.value = false;
      Sentry.captureException(error);
      useAlert(t('CONVERSATION.AUDIO_CONVERT_ERROR'));
      emit('recordError', error);
    } finally {
      isProcessing.value = false;
    }
  });

  record.value.on('record-progress', time => {
    emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => {
  if (!record.value || isProcessing.value) return;

  if (record.value.isActive()) {
    isProcessing.value = true;
    emit('recordProcessing');
    record.value.stopRecording();
  }
};

const startRecording = () => {
  if (!record.value || isProcessing.value) return;

  record.value.startRecording();
};

const toggleRecordingPauseResume = () => {
  if (!record.value || isProcessing.value) return;

  if (record.value.isRecording()) {
    record.value.pauseRecording();
    return;
  }

  if (record.value.isPaused()) {
    record.value.resumeRecording();
  }
};

const playPause = () => {
  if (hasRecording.value && !isRecording.value && !isRecordingPaused.value) {
    wavesurfer.value.playPause();
    isPlaying.value = !isPlaying.value;
  }
};

onMounted(() => {
  initWaveSurfer();
  startRecording();
});

onUnmounted(() => {
  if (currentAudioUrl.value) {
    URL.revokeObjectURL(currentAudioUrl.value);
    currentAudioUrl.value = null;
  }
  if (wavesurfer.value) {
    wavesurfer.value.destroy();
  }
});

defineExpose({ playPause, stopRecording, toggleRecordingPauseResume, record });
</script>

<template>
  <div ref="waveformContainer" class="w-full p-1" />
</template>
