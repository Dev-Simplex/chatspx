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
  return !!response.value.score;
});

const score = computed(() => {
  return response.value.score || null;
});
</script>

<template>
  <BaseBubble class="px-3 py-2" data-bubble-name="nps">
    <h4>
      {{
        content ||
        t('CONVERSATION.NPS_REPLY_MESSAGE', {
          default: 'De 0 a 10, o quanto você recomendaria nossa empresa?',
        })
      }}
    </h4>
    <dl v-if="isScoreSubmitted" class="mt-4">
      <dt class="text-n-slate-11 italic">
        {{ t('CONVERSATION.SCORE_TITLE', { default: 'Nota' }) }}
      </dt>
      <dd class="text-lg font-semibold">{{ score }}/10</dd>

      <dt v-if="response.comment" class="text-n-slate-11 italic mt-2">
        {{ t('CONVERSATION.COMMENT_TITLE', { default: 'Comentário' }) }}
      </dt>
      <dd>{{ response.comment }}</dd>
    </dl>
  </BaseBubble>
</template>
