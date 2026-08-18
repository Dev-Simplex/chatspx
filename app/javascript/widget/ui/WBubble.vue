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
  // 15/22 e 82% saem da §C; `shadow-none` é explícito porque a regra antiga
  // deste balão tinha sombra e o aceite do 2.03 mede `boxShadow === 'none'`.
  @apply max-w-[82%] px-3 py-2 text-[15px] leading-[22px] shadow-none
    rounded-[20px] break-words;

  &--incoming {
    @apply bg-n-solid-1 text-n-slate-12 rounded-bl-[6px];
  }

  &--outgoing {
    @apply text-n-slate-12 rounded-br-[6px];

    background-color: var(--w-brand);
    color: var(--w-on-brand);
  }
}
</style>
