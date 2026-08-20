<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  DEFAULT_EVENT_MAP,
  TRACKING_EVENTS,
  eventLabelKey,
} from '../composables/widgetTrackingContract';

/**
 * Os doze eventos, e para onde cada um vai.
 *
 * A lista NAO e escrita aqui: ela vem de `widgetTrackingContract`, que por sua
 * vez e conferido contra `docs/tracking/contrato-de-eventos.md` — a fonte da
 * verdade do bloco 5.03. Quem acrescentar um evento muda o documento, e o teste
 * cobra a tela.
 *
 * O mapa e gravado COMPLETO: quem consome le o que esta gravado, sem precisar
 * conhecer os defaults desta tela. Default implicito no consumidor e como as
 * duas pontas passam a discordar sem ninguem perceber.
 */
const props = defineProps({
  eventMap: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const linhas = computed(() =>
  TRACKING_EVENTS.map(nome => ({
    nome,
    ...DEFAULT_EVENT_MAP[nome],
    ...(props.eventMap[nome] ?? {}),
  }))
);

const label = nome =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(eventLabelKey(nome));

const alterar = (nome, patch) =>
  emit('update', {
    ...props.eventMap,
    [nome]: {
      ...DEFAULT_EVENT_MAP[nome],
      ...(props.eventMap[nome] ?? {}),
      ...patch,
    },
  });
</script>

<template>
  <div class="flex flex-col" data-testid="event-map">
    <div
      class="hidden gap-3 py-2 text-xs font-medium lg:grid lg:grid-cols-12 text-n-slate-11"
    >
      <span class="lg:col-span-5">
        {{ t('INBOX_WIDGET.TRACKING.EVENT_MAP.EVENT') }}
      </span>
      <span class="lg:col-span-3">
        {{ t('INBOX_WIDGET.TRACKING.EVENT_MAP.META') }}
      </span>
      <span class="lg:col-span-3">
        {{ t('INBOX_WIDGET.TRACKING.EVENT_MAP.GA4') }}
      </span>
      <span class="lg:col-span-1">
        {{ t('INBOX_WIDGET.TRACKING.EVENT_MAP.ON') }}
      </span>
    </div>

    <div
      v-for="linha in linhas"
      :key="linha.nome"
      class="grid items-center gap-3 py-2 border-b lg:grid-cols-12 border-n-weak"
      :data-testid="`event-${linha.nome}`"
    >
      <div class="lg:col-span-5">
        <p class="text-sm text-n-slate-12">{{ label(linha.nome) }}</p>
        <code class="text-xs text-n-slate-10">{{ linha.nome }}</code>
      </div>
      <div class="lg:col-span-3">
        <Input
          class="max-w-[12rem]"
          :model-value="linha.meta ?? ''"
          :placeholder="t('INBOX_WIDGET.TRACKING.EVENT_MAP.NOT_SENT')"
          :aria-label="t('INBOX_WIDGET.TRACKING.EVENT_MAP.META')"
          :data-testid="`meta-${linha.nome}`"
          @update:model-value="alterar(linha.nome, { meta: $event || null })"
        />
      </div>
      <div class="lg:col-span-3">
        <Input
          class="max-w-[12rem]"
          :model-value="linha.ga4 ?? ''"
          :placeholder="t('INBOX_WIDGET.TRACKING.EVENT_MAP.NOT_SENT')"
          :aria-label="t('INBOX_WIDGET.TRACKING.EVENT_MAP.GA4')"
          :data-testid="`ga4-${linha.nome}`"
          @update:model-value="alterar(linha.nome, { ga4: $event || null })"
        />
      </div>
      <div class="lg:col-span-1">
        <Switch
          :model-value="Boolean(linha.enabled)"
          :aria-label="label(linha.nome)"
          :data-testid="`enabled-${linha.nome}`"
          @update:model-value="alterar(linha.nome, { enabled: $event })"
        />
      </div>
    </div>
  </div>
</template>
