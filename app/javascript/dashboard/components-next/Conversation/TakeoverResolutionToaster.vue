<script setup>
// D1 (Fase 3) — avisa o SOLICITANTE, em qualquer tela, que seu pedido foi
// respondido. Renderless: só observa o store e emite um toast.
//
// Por que existe: no APROVADO o solicitante ganha a conversa (sinal claro), mas
// no NEGADO nada muda — sem este aviso ele ficaria sem saber. O sino guarda o
// registro durável; este toast é o feedback imediato.
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const store = useStore();
const { accountId } = useAccount();

const notice = useMapGetter('takeoverRequests/getResolvedNotice');

// Recado importante (aprovado/negado) — fica MAIS tempo que o toast padrão (2,5s)
// p/ dar tempo de ler e, no aprovado, de clicar em "Abrir conversa".
const APPROVED_DURATION = 12000;
const DENIED_DURATION = 10000;

watch(notice, value => {
  if (!value) return;

  if (value.status === 'approved') {
    // action.type='link' → o Snackbar renderiza um link p/ a conversa (agora minha).
    useAlert(t('CONVERSATION.TAKEOVER_RESULT.APPROVED'), {
      type: 'link',
      to: `/app/accounts/${accountId.value}/conversations/${value.conversationId}`,
      message: t('CONVERSATION.TAKEOVER_RESULT.OPEN'),
      duration: APPROVED_DURATION,
    });
  } else if (value.status === 'superseded') {
    // O pedido morreu porque outra pessoa assumiu a conversa antes.
    useAlert(t('CONVERSATION.TAKEOVER_RESULT.SUPERSEDED'), {
      duration: DENIED_DURATION,
    });
  } else {
    const message = value.note
      ? t('CONVERSATION.TAKEOVER_RESULT.DENIED_WITH_NOTE', { note: value.note })
      : t('CONVERSATION.TAKEOVER_RESULT.DENIED');
    useAlert(message, { duration: DENIED_DURATION });
  }

  // consome o aviso (senão reaparece ao remontar).
  store.dispatch('takeoverRequests/clearResolvedNotice');
});
</script>

<template>
  <!-- renderless -->
  <span class="hidden" aria-hidden="true" />
</template>
