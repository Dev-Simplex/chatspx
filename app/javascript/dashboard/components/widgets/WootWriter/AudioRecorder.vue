<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import * as Sentry from '@sentry/vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { convertAudio } from './utils/audioConversionUtils';

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
const recordedAudioUrl = ref(null);

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const AUDIO_EXTENSION_MAP = {
  'audio/ogg': 'ogg',
  'audio/mp3': 'mp3',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/webm': 'webm',
};

const getRecordPluginOptions = audioFormat => {
  const options = {
    scrollingWaveform: true,
    renderRecordedAudio: false,
  };
  if (
    audioFormat === 'audio/ogg' &&
    MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
  ) {
    options.mimeType = 'audio/ogg;codecs=opus';
  }
  return options;
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
      RecordPlugin.create(getRecordPluginOptions(props.audioRecordFormat)),
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
      const audioBlob = await convertAudio(blob, props.audioRecordFormat);
      // Use the converted blob's actual type, which may differ from the
      // requested format when the browser can't produce it (e.g. Safari falls
      // back to MP3 instead of OGG). This keeps the filename, content type, and
      // voice-note flag consistent with the real bytes.
      const audioType = audioBlob.type || props.audioRecordFormat;
      const ext = AUDIO_EXTENSION_MAP[audioType] || 'mp3';
      const fileName = `${getUuid()}.${ext}`;
      const file = new File([audioBlob], fileName, {
        type: audioType,
      });
      if (recordedAudioUrl.value) URL.revokeObjectURL(recordedAudioUrl.value);
      recordedAudioUrl.value = URL.createObjectURL(audioBlob);
      wavesurfer.value.load(recordedAudioUrl.value);
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
  if (recordedAudioUrl.value) {
    URL.revokeObjectURL(recordedAudioUrl.value);
    recordedAudioUrl.value = null;
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
