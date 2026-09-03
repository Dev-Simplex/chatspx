<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

/**
 * O aviso do nivel Agressivo (bloco 4.20).
 *
 * O nivel abre o painel sozinho. Ele existe, esta disponivel para toda conta e
 * nao tem gate de plano — o que este dialogo constroi e a POLITICA: o
 * administrador ve, antes de salvar, o que vai acontecer com o visitante.
 *
 * Tres pontos, e os tres sao consequencia, nao opiniao: o painel cobre o que a
 * pessoa estava lendo; abre no maximo uma vez por sessao e so depois do
 * gatilho; e em celular nao e aplicado, porque la ele ocupa a tela inteira.
 *
 * O texto NAO menciona penalizacao de buscador — e decisao de produto tomada
 * (4.20), e ha teste que varre as strings desta tela para garantir.
 */
const props = defineProps({
  open: { type: Boolean, default: false },
  /** O nivel que o celular vai continuar usando. */
  mobileLevel: { type: String, default: 'bold' },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
const dialogRef = ref(null);

watch(
  () => props.open,
  isOpen => (isOpen ? dialogRef.value?.open() : dialogRef.value?.close())
);

const nivelDoCelular = () =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.APPROACH.LEVELS.${props.mobileLevel.toUpperCase()}.LABEL`);
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    width="lg"
    :title="t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.TITLE')"
    :description="t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.CONFIRM')"
    :cancel-button-label="t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.CANCEL')"
    @confirm="emit('confirm')"
    @close="emit('cancel')"
  >
    <ul
      class="flex flex-col gap-2 pl-5 text-sm list-disc text-n-slate-11"
      data-testid="auto-open-points"
    >
      <li>
        {{ t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.POINT_INTERRUPTS') }}
      </li>
      <li>{{ t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.POINT_ONCE') }}</li>
      <li>
        {{
          t('INBOX_WIDGET.TRIGGERS.AUTO_OPEN_DIALOG.POINT_MOBILE', {
            level: nivelDoCelular(),
          })
        }}
      </li>
    </ul>
  </Dialog>
</template>
