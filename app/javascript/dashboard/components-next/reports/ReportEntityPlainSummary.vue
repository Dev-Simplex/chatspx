<script setup>
import { computed } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { formatDuration } from 'dashboard/helper/reportFormat';

// A tabela de Agentes / Caixas / Times / Etiquetas em poucas frases: quantos tiveram conversa, quem recebeu
// mais, quem respondeu mais rapido e mais devagar, e quantas foram resolvidas.
const props = defineProps({
  // agent | inbox | team | label
  type: { type: String, required: true },
  // [{ name, conversations, resolved, firstResponse }] com os valores crus
  rows: { type: Array, default: () => [] },
});

const { t } = useI18n();
const TYPE = computed(() => props.type.toUpperCase());

const active = computed(() =>
  props.rows.filter(row => Number(row.conversations) > 0)
);
const totalConversations = computed(() =>
  active.value.reduce((sum, row) => sum + Number(row.conversations), 0)
);
const totalResolved = computed(() =>
  active.value.reduce((sum, row) => sum + Number(row.resolved || 0), 0)
);
const busiest = computed(
  () =>
    [...active.value].sort((a, b) => b.conversations - a.conversations)[0] ||
    null
);
const byResponse = computed(() =>
  active.value
    .filter(row => Number(row.firstResponse) > 0)
    .sort((a, b) => a.firstResponse - b.firstResponse)
);
const fastest = computed(() => byResponse.value[0] || null);
const slowest = computed(() =>
  byResponse.value.length > 1
    ? byResponse.value[byResponse.value.length - 1]
    : null
);

const number = value => Number(value || 0).toLocaleString();
const time = seconds => formatDuration(seconds, t);
</script>

<template>
  <section
    v-if="active.length"
    class="mt-4 rounded-xl border border-n-weak bg-n-solid-2 p-5"
  >
    <h3 class="text-base font-semibold text-n-slate-12">
      {{ t('REPORT.PLAIN_SUMMARY.TITLE') }}
    </h3>
    <ul
      class="mt-3 flex flex-col gap-3 text-base leading-relaxed text-n-slate-12"
    >
      <li class="flex gap-3">
        <span
          class="i-lucide-message-circle size-5 mt-1 shrink-0 text-n-brand"
        />
        <span class="min-w-0">
          <I18nT :keypath="`REPORT.ENTITY_SUMMARY.${TYPE}.VOLUME`" tag="span">
            <template #count>
              <strong>{{ number(active.length) }}</strong>
            </template>
            <template #conversations>
              <strong>{{ number(totalConversations) }}</strong>
            </template>
          </I18nT>
          <template v-if="busiest && active.length > 1">
            {{ ' ' }}
            <I18nT
              :keypath="`REPORT.ENTITY_SUMMARY.${TYPE}.BUSIEST`"
              tag="span"
            >
              <template #name>
                <strong>{{ busiest.name }}</strong>
              </template>
              <template #conversations>
                <strong>{{ number(busiest.conversations) }}</strong>
              </template>
            </I18nT>
          </template>
        </span>
      </li>
      <li v-if="fastest" class="flex gap-3">
        <span class="i-lucide-timer size-5 mt-1 shrink-0 text-n-brand" />
        <span class="min-w-0">
          <I18nT keypath="REPORT.ENTITY_SUMMARY.FASTEST" tag="span">
            <template #name>
              <strong>{{ fastest.name }}</strong>
            </template>
            <template #time>
              <strong>{{ time(fastest.firstResponse) }}</strong>
            </template>
          </I18nT>
          <template v-if="slowest">
            {{ ' ' }}
            <I18nT keypath="REPORT.ENTITY_SUMMARY.SLOWEST" tag="span">
              <template #name>
                <strong>{{ slowest.name }}</strong>
              </template>
              <template #time>
                <strong>{{ time(slowest.firstResponse) }}</strong>
              </template>
            </I18nT>
          </template>
        </span>
      </li>
      <li class="flex gap-3">
        <span class="i-lucide-circle-check size-5 mt-1 shrink-0 text-n-brand" />
        <span class="min-w-0">
          <I18nT keypath="REPORT.ENTITY_SUMMARY.RESOLVED" tag="span">
            <template #resolved>
              <strong>{{ number(totalResolved) }}</strong>
            </template>
          </I18nT>
        </span>
      </li>
    </ul>
    <p class="mt-4 text-sm text-n-slate-11">
      {{ t('REPORT.ENTITY_SUMMARY.HOW_TO_READ') }}
    </p>
  </section>
</template>
