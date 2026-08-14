<script setup>
/**
 * Avatar do participante em conversa de grupo de WhatsApp.
 *
 * Não reaproveita `next/avatar/Avatar.vue` de propósito: lá as iniciais são as duas
 * primeiras palavras e a cor vem do comprimento do nome (6 baldes, colisão garantida
 * num grupo de 12). Aqui as iniciais e a cor vêm de `whatsappGroupHelper`, com
 * identidade estável e paleta verificada nos dois temas.
 *
 * O identificador técnico (LID) não entra em `title`, `alt` nem `aria-label`.
 *
 * Cor de fundo cheia com texto de alto contraste (branco no claro, quase-preto no
 * escuro): o avatar fica sobre o papel de parede da conversa, não sobre a bolha, e um
 * fundo translúcido derrubaria as iniciais para ~3,5:1. A paleta foi calibrada para
 * 4,5:1 contra o fundo da BOLHA — que é onde o nome é escrito, não o avatar.
 */
import { groupAuthorStyle } from './groupAuthorPresenter.js';

defineProps({
  author: { type: Object, required: true },
});
</script>

<template>
  <span
    v-tooltip.top="author.tooltip"
    role="img"
    :aria-label="author.ariaLabel"
    class="flex items-center justify-center font-bold leading-none rounded-lg select-none size-7 text-[11px] outline outline-1 -outline-offset-1 outline-[rgb(0_0_0_/_0.03)] dark:outline-[rgb(255_255_255_/_0.04)] bg-[var(--group-author-color)] text-white dark:bg-[var(--group-author-color-dark)] dark:text-[#0b141a]"
    :style="groupAuthorStyle(author)"
  >
    {{ author.initials }}
  </span>
</template>
