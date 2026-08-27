<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { messageStamp } from 'shared/helpers/timeHelper';
import WebhooksAPI from 'dashboard/api/webhooks';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

/**
 * Bloco 4.14 — a tela de entregas de um webhook.
 *
 * O ACEITE do bloco e uma frase de operacao: **a tela mostra a entrega falhada e o reenvio
 * chega com o MESMO `X-Chatwoot-Delivery`**. As duas metades estao aqui, e as duas tem um
 * jeito conhecido de dar errado:
 *
 *  · "mostra a falhada" — o log so vale se o MOTIVO aparecer. Uma lista de status coloridos
 *    sem `http_status` e sem `error_message` obriga o cliente a abrir chamado para descobrir
 *    o que ja esta gravado no banco;
 *  · "o mesmo delivery id" — quem preserva o identificador e o servidor (`WebhookDelivery#replay!`
 *    reusa o `delivery_id`). O front NAO o envia, e nao poderia: o que ele manda e a chave
 *    primaria da LINHA. Por isso o alerta de sucesso mostra o id que voltou da resposta — e a
 *    confirmacao visivel de que o destino vai conseguir deduplicar.
 *
 * SEGREDO NAO APARECE AQUI. Nem o do webhook, nem nada que se pareca com um: este componente
 * desenha uma lista fechada de colunas da entrega, e o `webhook` que ele recebe entra apenas
 * pelo `id` e pela `url`. Ha teste que monta esta tela com um webhook QUE TEM segredo e exige
 * que ele nao esteja no HTML renderizado.
 */
const props = defineProps({
  webhook: {
    type: Object,
    required: true,
  },
  onClose: {
    type: Function,
    required: true,
  },
});

const { t } = useI18n();

const deliveries = ref([]);
const isLoading = ref(false);
const loadError = ref('');
/** Id da linha em reenvio — trava so o botao dela, nao a tela inteira. */
const replayingId = ref(null);

/** Status que valem reenvio. Reenviar o que ja chegou duplicaria o evento no destino. */
const REPLAYABLE = ['failed'];

const carregar = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await WebhooksAPI.deliveries(props.webhook.id);
    deliveries.value = data?.payload?.deliveries ?? [];
  } catch (error) {
    loadError.value =
      error?.response?.data?.message ||
      error?.message ||
      t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.LOAD_ERROR');
    deliveries.value = [];
  } finally {
    isLoading.value = false;
  }
};

const reenviar = async delivery => {
  replayingId.value = delivery.id;
  try {
    const { data } = await WebhooksAPI.replay(props.webhook.id, delivery.id);
    // O id que voltou e o da entrega ORIGINAL — e o que o destino usa para deduplicar.
    useAlert(
      t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.REPLAY.SUCCESS', {
        deliveryId: data?.delivery_id ?? delivery.delivery_id,
      })
    );
    await carregar();
  } catch (error) {
    useAlert(t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.REPLAY.ERROR'));
  } finally {
    replayingId.value = null;
  }
};

const podeReenviar = delivery => REPLAYABLE.includes(delivery.status);

/** `--` e melhor que uma data invalida: diz "nao ha", em vez de mentir uma data. */
const formatarData = iso => {
  if (!iso) return '--';
  const emSegundos = Math.floor(new Date(iso).getTime() / 1000);
  if (Number.isNaN(emSegundos)) return '--';

  return messageStamp(emSegundos, 'LLL d yyyy, h:mm a');
};

const corDoStatus = status =>
  ({
    delivered: 'text-n-teal-11 bg-n-teal-3',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
    pending: 'text-n-amber-11 bg-n-amber-3',
  })[status] ?? 'text-n-slate-11 bg-n-slate-3';

const isEmpty = computed(() => !isLoading.value && !deliveries.value.length);

onMounted(carregar);
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="$t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.TITLE')"
      :header-content="
        $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.DESC', {
          webhookURL: webhook.url,
        })
      "
    />
    <div class="px-8 pb-6">
      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <p v-else-if="loadError" class="py-6 text-sm text-n-ruby-11">
        {{ loadError }}
      </p>

      <p v-else-if="isEmpty" class="py-6 text-sm text-n-slate-11">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.EMPTY') }}
      </p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th class="py-2 font-medium">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.HEADER.EVENT') }}
            </th>
            <th class="py-2 font-medium">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.HEADER.STATUS') }}
            </th>
            <th class="py-2 font-medium">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.HEADER.WHEN') }}
            </th>
            <th class="py-2 font-medium text-right">
              {{ $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.HEADER.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="delivery in deliveries"
            :key="delivery.id"
            class="border-t border-n-weak align-top"
          >
            <td class="py-3 pr-3">
              <span class="font-medium text-n-slate-12">
                {{ delivery.event }}
              </span>
              <span class="block font-mono text-xs text-n-slate-11">
                {{ delivery.delivery_id }}
              </span>
            </td>
            <td class="py-3 pr-3">
              <span
                class="inline-block px-2 py-0.5 rounded text-xs font-medium"
                :class="corDoStatus(delivery.status)"
              >
                {{ delivery.status }}
                <template v-if="delivery.http_status">
                  · {{ delivery.http_status }}
                </template>
              </span>
              <span
                v-if="delivery.error_message"
                class="block mt-1 text-xs text-n-ruby-11 break-words"
              >
                {{ delivery.error_message }}
              </span>
              <span
                v-if="delivery.attempts > 1"
                class="block mt-1 text-xs text-n-slate-11"
              >
                {{
                  $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.ATTEMPTS', {
                    count: delivery.attempts,
                  })
                }}
              </span>
            </td>
            <td class="py-3 pr-3 text-n-slate-11 whitespace-nowrap">
              {{ formatarData(delivery.delivered_at || delivery.created_at) }}
            </td>
            <td class="py-3 text-right">
              <NextButton
                v-if="podeReenviar(delivery)"
                sm
                faded
                slate
                :is-loading="replayingId === delivery.id"
                :disabled="replayingId === delivery.id"
                :label="
                  $t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.REPLAY.BUTTON')
                "
                @click="reenviar(delivery)"
              />
            </td>
          </tr>
        </tbody>
      </table>

      <div class="flex justify-end gap-2 mt-6">
        <NextButton
          faded
          slate
          :label="$t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.REFRESH')"
          :disabled="isLoading"
          @click="carregar"
        />
        <NextButton
          blue
          :label="$t('INTEGRATION_SETTINGS.WEBHOOK.DELIVERIES.CLOSE')"
          @click="props.onClose()"
        />
      </div>
    </div>
  </div>
</template>
