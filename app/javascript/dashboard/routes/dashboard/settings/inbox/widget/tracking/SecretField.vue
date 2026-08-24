<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

/**
 * Um campo de SEGREDO — e as duas metades da regra.
 *
 * A primeira todo mundo lembra: **nunca re-exibe**. O valor gravado nao volta
 * do servidor e nao aparece na tela; o que a tela mostra e o ESTADO ("definido
 * em 03/08") e a mascara.
 *
 * A segunda e a que ja custou caro nesta base, e e o motivo deste componente
 * existir separado: **salvar sem re-exibir nao pode APAGAR**. O defeito real
 * foi assim — o upstream passou a filtrar o campo na leitura, o formulario
 * continuou reenviando o objeto inteiro, e abrir "Editar" numa integracao
 * apagava a credencial do cliente. Nenhum dos dois lados estava errado
 * sozinho.
 *
 * A regra que este componente implementa, e que o teste cobra nos dois
 * sentidos: enquanto o administrador nao digitar um valor novo, o campo emite
 * `undefined` — que quem monta o payload deve tratar como "nao mexa nisto".
 * Nunca string vazia, que o servidor gravaria como "apague".
 *
 * O antipadrao oposto ja existe versionado neste repositorio
 * (`webhooks/_webhook.json.jbuilder` devolve segredo em texto claro), e e a
 * razao de o plano pedir o componente proprio.
 */
const props = defineProps({
  label: { type: String, required: true },
  /** Se ja existe segredo gravado. O VALOR nunca chega aqui. */
  isDefined: { type: Boolean, default: false },
  /**
   * Os QUATRO ultimos caracteres do que esta guardado — o unico pedaco do
   * segredo que o servidor devolve (`last_four` do contrato do 5.02).
   *
   * Existe para uma pergunta que o administrador faz de verdade: "o token que
   * esta ai e o novo que acabei de gerar ou o antigo?". Sem isso, dois tokens
   * validos sao indistinguiveis na tela e a unica forma de conferir e
   * substituir — que e justamente a operacao arriscada. Quatro caracteres
   * respondem e nao reconstituem nada.
   */
  lastFour: { type: String, default: '' },
  /** Quando foi definido, para a tela poder dizer. */
  definedAt: { type: String, default: '' },
  helpText: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  disabledReason: { type: String, default: '' },
});

/**
 * `change` leva o valor NOVO. Nao existe evento de "manteve" — a ausencia de
 * evento e o que significa manter.
 */
const emit = defineEmits(['change']);

const { t } = useI18n();

const emEdicao = ref(false);
const valor = ref('');

/**
 * A mascara tem tamanho FIXO — ela nao acompanha o comprimento do segredo.
 * Bolinha por caractere entregaria de graca quantos caracteres tem o token, que
 * e informacao que um atacante usa para escolher por onde comecar.
 *
 * Quando o servidor manda `last_four`, os quatro pontos finais dao lugar aos
 * quatro caracteres reais: `••••••••9f2a`. O total de doze nao muda.
 */
const mascara = computed(() => {
  if (!props.isDefined) return t('INBOX_WIDGET.TRACKING.SECRET.EMPTY');

  const fim = props.lastFour.slice(-4);
  return fim ? `${'•'.repeat(12 - fim.length)}${fim}` : '••••••••••••';
});

const estado = computed(() => {
  if (!props.isDefined) return t('INBOX_WIDGET.TRACKING.SECRET.NOT_SET');
  return props.definedAt
    ? t('INBOX_WIDGET.TRACKING.SECRET.SET_AT', { date: props.definedAt })
    : t('INBOX_WIDGET.TRACKING.SECRET.SET');
});

const comecarTroca = () => {
  emEdicao.value = true;
  valor.value = '';
};

const cancelar = () => {
  emEdicao.value = false;
  valor.value = '';
  // Nao emite nada: cancelar e exatamente "nao mexa no que esta gravado".
};

const confirmar = () => {
  const novo = valor.value.trim();
  if (!novo) return;
  emit('change', novo);
  emEdicao.value = false;
  valor.value = '';
};
</script>

<template>
  <div class="flex flex-col gap-2" :data-testid="`secret-${label}`">
    <span class="text-sm font-medium text-n-slate-12">{{ label }}</span>

    <template v-if="emEdicao">
      <Input
        v-model="valor"
        type="password"
        class="max-w-md"
        autocomplete="off"
        :aria-label="label"
        data-testid="secret-input"
      />
      <div class="flex gap-2">
        <NextButton
          :label="t('INBOX_WIDGET.TRACKING.SECRET.CONFIRM')"
          :disabled="!valor.trim()"
          data-testid="secret-confirm"
          @click="confirmar"
        />
        <NextButton
          faded
          slate
          :label="t('INBOX_WIDGET.TRACKING.SECRET.CANCEL')"
          data-testid="secret-cancel"
          @click="cancelar"
        />
      </div>
    </template>

    <template v-else>
      <div class="flex items-center gap-3">
        <span
          class="font-mono text-sm select-none text-n-slate-11"
          data-testid="secret-mask"
        >
          {{ mascara }}
        </span>
        <NextButton
          faded
          slate
          :label="
            isDefined
              ? t('INBOX_WIDGET.TRACKING.SECRET.REPLACE')
              : t('INBOX_WIDGET.TRACKING.SECRET.SET_BUTTON')
          "
          :disabled="disabled"
          data-testid="secret-replace"
          @click="comecarTroca"
        />
      </div>
      <span class="text-sm text-n-slate-11" data-testid="secret-state">
        {{ estado }}
      </span>
    </template>

    <p
      v-if="disabled && disabledReason"
      class="text-sm text-n-amber-12"
      data-testid="secret-disabled-reason"
    >
      {{ disabledReason }}
    </p>
    <p v-else-if="helpText" class="text-sm text-n-slate-11">{{ helpText }}</p>
  </div>
</template>
