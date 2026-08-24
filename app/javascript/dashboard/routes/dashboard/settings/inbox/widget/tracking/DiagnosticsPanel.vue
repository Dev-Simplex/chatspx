<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import {
  redactPii,
  sanitizeDelivery,
  sanitizeDeliveries,
} from './trackingRedaction';
import { EMQ_HEALTHY } from './useTrackingDiagnostics';

/**
 * O painel de auditoria (bloco 5.14, T-C8.3/T-C8.5, T4.6/T4.7).
 *
 * O aceite e operacional: **um agente de suporte responde "o evento saiu?" sem
 * abrir console de ninguem**. O painel responde isso em quatro camadas, da
 * pergunta mais comum para a mais especifica: o resumo (quanto sai), os erros
 * agrupados (por que nao sai), a lista (o que saiu agora), e o botao de teste
 * (sai AGORA se eu mandar?).
 *
 * REGRA DURA DE PRIVACIDADE, e ela e o motivo de este painel ter desenho
 * proprio: mostra **os NOMES** dos campos enviados, nunca os valores. Nem em
 * claro, nem hasheado. Um painel de diagnostico que exibe e-mail de lead e um
 * vazamento com interface.
 *
 * A limpeza e refeita AQUI, mesmo o composable ja limpando na leitura. Nao e
 * paranoia decorativa: `error_message` e texto livre devolvido pelo destino, e
 * a Graph API da Meta ecoa o parametro ofensivo dentro da mensagem
 * ("Invalid parameter: em (...) is not a valid hash"). Quem montar este
 * componente com dado vindo de outro caminho — um teste, um mock, uma tela
 * futura — tem de continuar sem conseguir vazar. Por isso a fronteira e o
 * componente, nao o chamador.
 */
const props = defineProps({
  deliveries: { type: Array, default: () => [] },
  deliveryRate: { type: Number, default: null },
  errorGroups: { type: Array, default: () => [] },
  emqAverage: { type: Number, default: null },
  retentionDays: { type: Number, default: 0 },
  isLoading: { type: Boolean, default: false },
  isSendingTest: { type: Boolean, default: false },
  /** O caminho da rota que ainda nao existe — a tela NOMEIA o que falta. */
  missingEndpoint: { type: String, default: '' },
  loadError: { type: String, default: '' },
  testResult: { type: Object, default: null },
});

const emit = defineEmits(['test', 'refresh']);

const { t } = useI18n();

/** Segunda passada da tesoura: quem monta este componente nao escolhe vazar. */
const linhas = computed(() => sanitizeDeliveries(props.deliveries));

const grupos = computed(() =>
  props.errorGroups.map(grupo => ({
    ...grupo,
    // O mesmo motivo da linha: `message` e texto livre do destino.
    message: redactPii(grupo.message),
  }))
);

const emqSaudavel = computed(
  () => props.emqAverage !== null && props.emqAverage >= EMQ_HEALTHY
);

const resultadoDoTeste = computed(() =>
  props.testResult ? sanitizeDelivery(props.testResult) : null
);
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="diagnostics-panel">
    <Banner color="slate" data-testid="diagnostics-privacy">
      <span class="text-n-slate-12">
        {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.PRIVACY') }}
      </span>
    </Banner>

    <!-- ── O que responde "o evento saiu?" antes de olhar linha a linha ── -->
    <div
      class="grid gap-3 sm:grid-cols-3"
      data-testid="diagnostics-summary"
    >
      <div class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak">
        <span class="text-xs text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.RATE') }}
        </span>
        <span
          class="text-lg font-medium text-n-slate-12"
          data-testid="diagnostics-rate"
        >
          {{
            deliveryRate === null
              ? t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.NO_DATA')
              : `${deliveryRate}%`
          }}
        </span>
      </div>

      <div class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak">
        <span class="text-xs text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EMQ') }}
        </span>
        <span
          class="text-lg font-medium"
          :class="emqSaudavel ? 'text-n-teal-11' : 'text-n-slate-12'"
          data-testid="diagnostics-emq"
        >
          {{
            emqAverage === null
              ? t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.NO_DATA')
              : emqAverage
          }}
        </span>
        <span class="text-xs text-n-slate-10">
          {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EMQ_HINT', {
            healthy: EMQ_HEALTHY,
          }) }}
        </span>
      </div>

      <div class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak">
        <span class="text-xs text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.RETENTION') }}
        </span>
        <span
          class="text-lg font-medium text-n-slate-12"
          data-testid="diagnostics-retention"
        >
          {{
            retentionDays
              ? t('INBOX_WIDGET.TRACKING.ACCOUNT.RETENTION_DAYS', {
                  days: retentionDays,
                })
              : t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.NO_DATA')
          }}
        </span>
      </div>
    </div>

    <!-- ── "Sai agora se eu mandar?" ─────────────────────────────────── -->
    <div class="flex flex-wrap items-center gap-3">
      <NextButton
        :label="t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.SEND_TEST')"
        :is-loading="isSendingTest"
        :disabled="isSendingTest"
        data-testid="diagnostics-send-test"
        @click="emit('test')"
      />
      <NextButton
        faded
        slate
        :label="t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.REFRESH')"
        :is-loading="isLoading"
        data-testid="diagnostics-refresh"
        @click="emit('refresh')"
      />
      <span
        v-if="resultadoDoTeste"
        class="text-sm text-n-slate-11"
        data-testid="diagnostics-test-result"
      >
        {{
          t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.TEST_RESULT', {
            status: resultadoDoTeste.status,
            http: resultadoDoTeste.http_status ?? '—',
          })
        }}
        <span v-if="resultadoDoTeste.error_message" class="text-n-ruby-11">
          {{ resultadoDoTeste.error_message }}
        </span>
      </span>
    </div>

    <Banner
      v-if="missingEndpoint"
      color="amber"
      data-testid="diagnostics-unavailable"
    >
      <span class="text-n-amber-12">
        {{
          t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.UNAVAILABLE', {
            path: missingEndpoint,
          })
        }}
      </span>
    </Banner>

    <Banner v-else-if="loadError" color="ruby" data-testid="diagnostics-error">
      <span class="text-n-ruby-12">{{ loadError }}</span>
    </Banner>

    <!-- ── "Por que não sai?" — o mesmo erro cem vezes é UM problema ─── -->
    <div
      v-if="grupos.length"
      class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak"
      data-testid="diagnostics-error-groups"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.ERRORS') }}
      </span>
      <div
        v-for="grupo in grupos"
        :key="grupo.key"
        class="flex items-baseline justify-between gap-3 text-sm"
        :data-testid="`error-group-${grupo.key}`"
      >
        <span class="text-n-ruby-11">
          {{ grupo.message || grupo.key }}
        </span>
        <span class="text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.TIMES', {
            count: grupo.count,
          }) }}
        </span>
      </div>
    </div>

    <p
      v-if="!linhas.length && !missingEndpoint"
      class="text-sm text-n-slate-11"
      data-testid="diagnostics-empty"
    >
      {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EMPTY') }}
    </p>

    <div v-if="linhas.length" class="overflow-x-auto">
      <table class="w-full text-sm" data-testid="diagnostics-table">
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
              {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EMQ') }}
            </th>
            <th class="py-1 font-medium">
              {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.FIELDS') }}
            </th>
            <th class="py-1 font-medium">
              {{ t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.EVENT_ID') }}
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
            <td class="py-1 text-n-slate-11">{{ linha.emq ?? '—' }}</td>
            <td
              class="py-1 text-n-slate-11"
              :data-testid="`fields-${linha.event_id}`"
            >
              {{ linha.field_names.join(', ') }}
            </td>
            <!--
              O identificador e o que o agente de suporte COPIA para o cliente
              conferir no Gerenciador de Eventos. Sem ele o painel diz que o
              evento saiu e nao da como provar qual.
            -->
            <td class="py-1 font-mono text-xs text-n-slate-10">
              {{ linha.event_id }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
