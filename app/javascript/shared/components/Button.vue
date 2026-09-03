<script>
export default {
  props: {
    block: {
      type: Boolean,
      default: false,
    },
    type: {
      type: String,
      default: 'blue',
    },
    bgColor: {
      type: String,
      default: '',
    },
    textColor: {
      type: String,
      default: '',
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    buttonClassName() {
      // `text-white` saiu: este botão pinta o fundo com a marca, e quem decide
      // a cor legível SOBRE a marca é `--w-on-brand` (luminância WCAG, no
      // servidor). Antes os chamadores passavam `:text-color` com o YIQ; ao
      // removê-lo, deixar `text-white` cravado trocaria uma adaptação imprecisa
      // por nenhuma — com marca clara o rótulo ficaria branco sobre claro.
      let className =
        'text-w-on-brand py-3 px-4 rounded-lg shadow-sm leading-4 cursor-pointer disabled:opacity-50';
      if (this.type === 'clear') {
        className = 'flex mx-auto mt-4 text-xs leading-3 w-auto text-n-gray-12';
      }

      if (this.type === 'blue' && !Object.keys(this.buttonStyles).length) {
        className = `${className} bg-w-brand hover:bg-w-brand-hover`;
      }
      if (this.block) {
        className = `${className} w-full`;
      }
      return className;
    },
    buttonStyles() {
      const styles = {};
      if (this.bgColor) {
        styles.backgroundColor = this.bgColor;
      }
      if (this.textColor) {
        styles.color = this.textColor;
      }
      return styles;
    },
  },
};
</script>

<template>
  <button :class="buttonClassName" :style="buttonStyles" :disabled="disabled">
    <slot />
  </button>
</template>
