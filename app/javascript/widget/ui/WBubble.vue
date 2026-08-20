<script>
/**
 * Balão de mensagem.
 *
 * A geometria vem da §C do plano e é o que o bloco 2.03 fixa: raio 20 px, com
 * 6 px no canto que aponta para o autor; `max-width` 82 %; corpo 15/22; e
 * **sem sombra** — a separação vem do contraste de fundo, não de elevação.
 */
const DIRECOES = {
  incoming: 'w-bubble--incoming',
  outgoing: 'w-bubble--outgoing',
};

export default {
  name: 'WBubble',
  props: {
    direction: {
      type: String,
      required: true,
      validator: valor => Object.keys(DIRECOES).includes(valor),
    },
  },
  computed: {
    classeDirecao() {
      return DIRECOES[this.direction];
    },
  },
};
</script>

<template>
  <div class="w-bubble" :class="classeDirecao">
    <slot />
  </div>
</template>

<style scoped lang="scss">
.w-bubble {
  // ── Correção do 2.03 sobre o que o 2.01 escreveu ─────────────────────────
  //
  // Este bloco nasceu com `@apply … shadow-none` e os cinco números cravados
  // (82%, 15px, 22px, 20px, 6px). As duas coisas estavam erradas, e a primeira
  // reprovava o próprio aceite que o comentário citava:
  //
  //   `shadow-none` do Tailwind NÃO produz `box-shadow: none`. Ele emite
  //   `box-shadow: var(--tw-ring-offset-shadow,0 0 #0000),
  //                var(--tw-ring-shadow,0 0 #0000), 0 0 #0000`,
  //   que o navegador computa como `rgba(0, 0, 0, 0) 0px 0px 0px 0px`.
  //   O aceite do 2.03 é `getComputedStyle(bolha).boxShadow === 'none'` — e
  //   essa string não é essa. Medido em Chromium, não deduzido.
  //
  // Os números agora saem de `widget-shape` (`_tokens_values.scss`), que é a
  // mesma fonte de `_conversation.scss`: um primitivo com a geometria cravada
  // é uma segunda cópia livre para divergir do balão real sem ninguém ver.
  @apply max-w-[var(--w-bubble-max-width)] px-3 py-2 break-words;

  border-radius: var(--w-bubble-radius);
  box-shadow: var(--w-bubble-shadow);
  font-size: var(--w-bubble-font-size);
  line-height: var(--w-bubble-line-height);

  &--incoming {
    @apply bg-n-solid-1 text-n-slate-12
      rounded-bl-[var(--w-bubble-radius-tail)];
  }

  &--outgoing {
    @apply rounded-br-[var(--w-bubble-radius-tail)];

    background-color: var(--w-brand);
    color: var(--w-on-brand);
  }
}
</style>
