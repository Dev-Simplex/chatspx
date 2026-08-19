<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';

/**
 * O diagnostico — a camada C8 (bloco 5.06 / T-C1.8).
 *
 * REGRA DURA DE PRIVACIDADE, e ela e o motivo de este painel existir com
 * desenho proprio: o log mostra **os NOMES** dos campos enviados, nunca os
 * valores. Nem em claro, nem hasheado. Um painel de diagnostico que exibe
 * e-mail de lead e um vazamento com interface.
 *
 * A tabela `tracking_deliveries` (bloco 5.03) ja guarda exatamente isso:
 * `field_names` e jsonb de NOMES, e o proprio contrato diz "nunca valores".
 * Este componente so sabe desenhar o que recebe — e o que ele recusa a
 * desenhar esta coberto por teste.
 */
const props = defineProps({
  deliveries: { type: Array, default: () => [] },
  /** Enquanto a leitura do log nao existir, a tela diz por que esta vazia. */
  unavailableReason: { type: String, default: '' },
});

const { t } = useI18n();

const linhas = computed(() =>
  props.deliveries.map(entrega => ({
    ...entrega,
    // Defesa em profundidade: se algum dia o servidor mandar valores junto, a
    // tela ainda mostra so os NOMES.
    fieldNames: Array.isArray(entrega.field_names)
      ? entrega.field_names.map(campo =>
          typeof campo === 'string' ? campo : Object.keys(campo ?? {})[0]
        )
      : [],
  }))
);
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="diagnostics-panel">
    <Banner color="slate" data-testid="diagnostics-privacy">
      <span class="text-n-slate-12">
        {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.PRIVACY') }}
      </span>
    </Banner>

    <Banner
      v-if="unavailableReason"
      color="amber"
      data-testid="diagnostics-unavailable"
    >
      <span class="text-n-amber-12">{{ unavailableReason }}</span>
    </Banner>

    <p
      v-else-if="!linhas.length"
      class="text-sm text-n-slate-11"
      data-testid="diagnostics-empty"
    >
      {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EMPTY') }}
    </p>

    <table v-else class="w-full text-sm" data-testid="diagnostics-table">
      <thead>
        <tr class="text-xs text-left text-n-slate-11">
          <th class="py-1 font-medium">
            {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.TIME') }}
          </th>
          <th class="py-1 font-medium">
            {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EVENT') }}
          </th>
          <th class="py-1 font-medium">
            {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.DESTINATION') }}
          </th>
          <th class="py-1 font-medium">
            {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.STATUS') }}
          </th>
          <th class="py-1 font-medium">
            {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.FIELDS') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="linha in linhas"
          :key="`${linha.event_id}-${linha.destination}`"
          class="border-t border-n-weak"
          :data-testid="`delivery-${linha.event_id}-${linha.destination}`"
        >
          <td class="py-1 text-n-slate-11">{{ linha.last_attempted_at }}</td>
          <td class="py-1 text-n-slate-12">{{ linha.name }}</td>
          <td class="py-1 text-n-slate-11">{{ linha.destination }}</td>
          <td class="py-1 text-n-slate-11">
            {{ linha.http_status || linha.status }}
            <span
              v-if="linha.error_message"
              class="block text-xs text-n-ruby-11"
            >
              {{ linha.error_message }}
            </span>
          </td>
          <td
            class="py-1 text-n-slate-11"
            :data-testid="`fields-${linha.event_id}`"
          >
            {{ linha.fieldNames.join(', ') }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
