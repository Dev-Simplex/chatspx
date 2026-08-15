<script setup>
/**
 * Nome do participante no topo da bolha, no padrão do WhatsApp: 13px semibold, na cor
 * determinística do autor. Aparece só na primeira mensagem do bloco.
 *
 * Quem não foi identificado fica em itálico e cor neutra — nunca com cor da paleta,
 * senão "não sei quem é" parece uma pessoa a mais no grupo.
 *
 * O telefone vive apenas no tooltip; o identificador técnico (LID), em lugar nenhum.
 */
import { groupAuthorStyle } from '../groupAuthorPresenter.js';

defineProps({
  author: { type: Object, required: true },
});
</script>

<template>
  <span
    v-tooltip.top="author.tooltip"
    tabindex="0"
    class="block mb-0.5 max-w-full truncate text-[13px] leading-tight text-[var(--group-author-color)] dark:text-[var(--group-author-color-dark)] focus-visible:outline-none focus-visible:underline"
    :class="author.isUnknown ? 'italic font-medium' : 'font-semibold'"
    :style="groupAuthorStyle(author)"
  >
    {{ author.label }}
  </span>
</template>
