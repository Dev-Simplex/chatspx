<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider.js';

const { contentAttributes, content } = useMessageContext();
const { t } = useI18n();

const response = computed(() => {
  return contentAttributes.value?.submittedValues?.npsResponse ?? {};
});

const isScoreSubmitted = computed(() => {
  return response.value.score !== undefined && response.value.score !== null;
});

const score = computed(() => {
  return isScoreSubmitted.value ? response.value.score : null;
});

const classification = computed(() => {
  if (!isScoreSubmitted.value) return null;
  const s = response.value.score;
  if (s >= 9) {
    return {
      label: t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promoter' }),
      color: 'text-green-600',
    };
  }
  if (s >= 7) {
    return {
      label: t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passive' }),
      color: 'text-yellow-600',
    };
  }
  return {
    label: t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detractor' }),
    color: 'text-red-600',
  };
});
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="nps">
    <h4>
      {{
        content ||
        t('CONVERSATION.NPS_REPLY_MESSAGE', {
          default:
            'On a scale of 0 to 10, how likely are you to recommend our company?',
        })
      }}
    </h4>
    <dl v-if="isScoreSubmitted" class="mt-4">
      <dt class="text-n-slate-11 italic">
        {{ t('CONVERSATION.SCORE_TITLE', { default: 'Score' }) }}
      </dt>
      <dd class="flex items-center gap-2">
        <span class="text-lg font-semibold">
          {{
            t('CONVERSATION.SCORE_FORMAT', { score, default: `${score}/10` })
          }}
        </span>
        <span
          v-if="classification"
          class="text-xs font-medium px-2 py-0.5 rounded-full"
          :class="classification.color"
        >
          {{ classification.label }}
        </span>
      </dd>

      <dt v-if="response.comment" class="text-n-slate-11 italic mt-2">
        {{ t('CONVERSATION.COMMENT_TITLE', { default: 'Comment' }) }}
      </dt>
      <dd v-if="response.comment">
        {{ response.comment }}
      </dd>
    </dl>
  </BaseBubble>
</template>
