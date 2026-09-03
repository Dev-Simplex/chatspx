<script>
import { rotuloObrigatorio } from './rotulos';
import WIconButton from './WIconButton.vue';

/**
 * Botão "descer para o fim", com contador de não lidas.
 *
 * Existe por causa do aceite do 2.04: mensagem chegando com o visitante rolado
 * para cima NÃO pode arrancá-lo da leitura — então é preciso oferecer o
 * caminho de volta em vez de forçar o scroll.
 */
export default {
  name: 'WScrollToBottom',
  components: { WIconButton },
  props: {
    label: {
      type: String,
      required: true,
      validator: rotuloObrigatorio,
    },
    count: {
      type: Number,
      default: 0,
      validator: valor => Number.isInteger(valor) && valor >= 0,
    },
  },
  emits: ['click'],
  computed: {
    // O contador entra no nome acessível: "Ver mensagens novas (3)" diz mais
    // que um número que só existe em pixel.
    nomeAcessivel() {
      return this.count > 0 ? `${this.label} (${this.count})` : this.label;
    },
  },
};
</script>

<template>
  <div class="w-scroll-to-bottom">
    <WIconButton :label="nomeAcessivel" @click="$emit('click')">
      <slot />
      <span v-if="count > 0" class="w-scroll-to-bottom__contador">
        {{ count }}
      </span>
    </WIconButton>
  </div>
</template>

<style scoped lang="scss">
.w-scroll-to-bottom {
  @apply relative inline-flex;

  &__contador {
    @apply absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full
      text-xs font-medium flex items-center justify-center;

    background-color: var(--w-brand);
    color: var(--w-on-brand);
  }
}
</style>
