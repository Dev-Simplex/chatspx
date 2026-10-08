<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatChange } from 'dashboard/helper/reportFormat';

// Um numero do painel: rotulo, valor, frase curta e a variacao contra o periodo anterior.
// A cor da variacao diz se foi bom ou ruim (lowerIsBetter para tempos); volume fica neutro.
const props = defineProps({
  icon: { type: String, required: true },
  label: { type: String, required: true },
  value: { type: String, required: true },
  caption: { type: String, default: '' },
  // variacao em %, null quando nao da para comparar
  change: { type: Number, default: null },
  // 'higher' | 'lower' | 'neutral'
  better: { type: String, default: 'neutral' },
  vsLabel: { type: String, default: '' },
  clickable: { type: Boolean, default: false },
});

const emit = defineEmits(['open']);
const { t } = useI18n();

const changeInfo = computed(() =>
  props.change === null ? null : formatChange(props.change, t)
);

const tone = computed(() => {
  const dir = changeInfo.value?.direction;
  if (!dir || dir === 'same' || props.better === 'neutral') return 'neutral';
  const good = props.better === 'higher' ? dir === 'up' : dir === 'down';
  return good ? 'good' : 'bad';
});

const pillClass = computed(
  () =>
    ({
      good: 'bg-n-teal-3 text-n-teal-11',
      bad: 'bg-n-ruby-3 text-n-ruby-11',
      neutral: 'bg-n-alpha-2 text-n-slate-11',
    })[tone.value]
);

const arrow = computed(
  () =>
    ({ up: 'i-lucide-arrow-up-right', down: 'i-lucide-arrow-down-right' })[
      changeInfo.value?.direction
    ] || 'i-lucide-equal'
);
</script>

<template>
  <component
    :is="clickable ? 'button' : 'div'"
    :type="clickable ? 'button' : undefined"
    class="flex flex-col gap-1 p-4 m-0 text-left rounded-xl border border-n-weak bg-n-solid-2 min-w-0"
    :class="
      clickable
        ? 'cursor-pointer transition-shadow hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand'
        : ''
    "
    :title="clickable ? t('REPORTS_PANEL.KPI.SEE_CONVERSATIONS') : undefined"
    @click="clickable && emit('open')"
  >
    <div class="flex items-start justify-between gap-2">
      <span
        class="flex items-center justify-center rounded-lg size-9 bg-n-alpha-2 text-n-slate-11"
      >
        <span class="size-5" :class="icon" />
      </span>
      <span
        v-if="changeInfo"
        class="inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-semibold"
        :class="pillClass"
        :title="`${changeInfo.text} ${vsLabel}`"
      >
        <span class="size-3" :class="arrow" />
        {{ changeInfo.text }}
      </span>
    </div>
    <span class="mt-2 text-sm text-n-slate-11">{{ label }}</span>
    <span
      class="text-3xl font-semibold tracking-tight text-n-slate-12 tabular-nums truncate"
    >
      {{ value }}
    </span>
    <span v-if="caption" class="text-xs text-n-slate-10">{{ caption }}</span>
  </component>
</template>
