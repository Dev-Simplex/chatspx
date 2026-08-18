<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { fieldLabelKey } from '../composables/widgetFieldLabels';

/**
 * O aviso de override.
 *
 * A regra de precedência (bloco 3.18) é: **o banco é o padrão, o
 * `chatwootSettings` do site do cliente sobrescreve, e a tela declara**. Sem
 * este aviso a tela mostraria "direita" enquanto o visitante vê o widget à
 * esquerda — o pior estado possível para uma tela de configuração, porque o
 * administrador não tem como descobrir sozinho.
 */
const props = defineProps({
  /** Campos de `widget_appearance` sobrescritos no snippet do site. */
  overriddenFields: { type: Array, default: () => [] },
});

const { t } = useI18n();

const nomes = computed(() =>
  props.overriddenFields
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    .map(field => t(fieldLabelKey(`appearance.${field}`)))
    .join(', ')
);
</script>

<template>
  <Banner
    v-if="overriddenFields.length"
    color="amber"
    data-testid="override-banner"
  >
    <div class="flex flex-col gap-1">
      <span class="font-medium">
        {{ t('INBOX_WIDGET.APPEARANCE.OVERRIDE.TITLE') }}
      </span>
      <span>
        {{ t('INBOX_WIDGET.APPEARANCE.OVERRIDE.BODY', { fields: nomes }) }}
      </span>
    </div>
  </Banner>
</template>
