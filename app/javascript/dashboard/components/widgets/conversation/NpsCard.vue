<template>
  <div class="nps-card p-4 border-b border-n-weak">
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-sm font-semibold">NPS</h3>
      <span
        class="text-xs px-2 py-1 rounded"
        :class="statusClass"
      >
        {{ statusText }}
      </span>
    </div>

    <div v-if="npsResponse">
      <div v-if="npsResponse.status === 'responded' && npsResponse.score !== null">
        <div class="flex items-center gap-2 mb-2">
          <span class="text-2xl font-bold">{{ npsResponse.score }}/10</span>
          <span class="text-xs px-2 py-1 rounded" :class="classificationClass">
            {{ classificationText }}
          </span>
        </div>
        <p
          v-if="npsResponse.comment"
          class="text-sm text-n-slate-11 mt-2"
        >
          {{ npsResponse.comment }}
        </p>
      </div>

      <div v-else-if="npsResponse.status === 'dismissed'">
        <p class="text-xs text-n-slate-11">
          Bloqueado por etiqueta: {{ npsResponse.blocked_by_label }}
        </p>
      </div>
    </div>

    <div class="mt-3 flex gap-2">
      <button
        v-if="canSend"
        class="text-xs px-3 py-1 bg-slate-100 rounded hover:bg-slate-200"
        @click="sendNps"
      >
        Enviar NPS
      </button>
      <button
        v-if="canResend"
        class="text-xs px-3 py-1 bg-slate-100 rounded hover:bg-slate-200"
        @click="resendNps"
      >
        Reenviar
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  npsResponse: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['send-nps', 'resend-nps']);

const { t } = useI18n();

const statusText = computed(() => {
  if (!props.npsResponse) return t('NPS.STATUS.NOT_SENT', { default: 'Não enviado' });
  
  const status = props.npsResponse.status;
  const statusMap = {
    sent: t('NPS.STATUS.SENT', { default: 'Enviado' }),
    responded: t('NPS.STATUS.RESPONDED', { default: 'Respondido' }),
    expired: t('NPS.STATUS.EXPIRED', { default: 'Expirado' }),
    dismissed: t('NPS.STATUS.BLOCKED', { default: 'Bloqueado' }),
    blocked: t('NPS.STATUS.BLOCKED', { default: 'Bloqueado' }),
  };
  
  return statusMap[status] || status;
});

const statusClass = computed(() => {
  if (!props.npsResponse) return 'bg-slate-100 text-slate-700';
  
  const status = props.npsResponse.status;
  const classMap = {
    sent: 'bg-blue-100 text-blue-700',
    responded: 'bg-green-100 text-green-700',
    expired: 'bg-yellow-100 text-yellow-700',
    dismissed: 'bg-red-100 text-red-700',
  };
  
  return classMap[status] || 'bg-slate-100 text-slate-700';
});

const classificationText = computed(() => {
  if (!props.npsResponse || !props.npsResponse.classification) return '';
  
  const classification = props.npsResponse.classification;
  const textMap = {
    promoter: t('NPS.CLASSIFICATION.PROMOTER', { default: 'Promotor' }),
    passive: t('NPS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
    detractor: t('NPS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' }),
  };
  
  return textMap[classification] || '';
});

const classificationClass = computed(() => {
  if (!props.npsResponse || !props.npsResponse.classification) return '';
  
  const classification = props.npsResponse.classification;
  const classMap = {
    promoter: 'bg-green-100 text-green-700',
    passive: 'bg-yellow-100 text-yellow-700',
    detractor: 'bg-red-100 text-red-700',
  };
  
  return classMap[classification] || '';
});

const canSend = computed(() => {
  return !props.npsResponse && props.conversation.inbox?.nps_survey_enabled;
});

const canResend = computed(() => {
  if (!props.npsResponse) return false;
  return props.npsResponse.status === 'expired' || props.npsResponse.status === 'sent';
});

const sendNps = () => {
  emit('send-nps');
};

const resendNps = () => {
  emit('resend-nps');
};
</script>
