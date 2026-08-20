<script>
/**
 * Faixa de aviso (offline, erro de envio, indisponibilidade).
 *
 * `tone` escolhe o papel ARIA: `alert` interrompe o leitor de tela e só cabe em
 * erro; aviso e informação usam `status`, que espera a pausa.
 */
const TONS = {
  info: { classe: 'w-banner--info', role: 'status' },
  warning: { classe: 'w-banner--warning', role: 'status' },
  error: { classe: 'w-banner--error', role: 'alert' },
};

export default {
  name: 'WBanner',
  props: {
    tone: {
      type: String,
      default: 'info',
      validator: valor => Object.keys(TONS).includes(valor),
    },
  },
  computed: {
    tom() {
      return TONS[this.tone] || TONS.info;
    },
  },
};
</script>

<template>
  <div class="w-banner" :class="tom.classe" :role="tom.role">
    <slot />
  </div>
</template>

<style scoped lang="scss">
.w-banner {
  @apply flex items-center gap-2 px-3 py-2 text-sm rounded-lg;

  &--info {
    @apply bg-n-alpha-2 text-n-slate-12;
  }

  &--warning {
    @apply bg-n-amber-3 text-n-amber-11;
  }

  &--error {
    @apply bg-n-ruby-3 text-n-ruby-11;
  }
}
</style>
