import path from 'path';

export const aliases = {
  vue: 'vue/dist/vue.esm-bundler.js',
  components: path.resolve('./app/javascript/dashboard/components'),
  next: path.resolve('./app/javascript/dashboard/components-next'),
  v3: path.resolve('./app/javascript/v3'),
  dashboard: path.resolve('./app/javascript/dashboard'),
  helpers: path.resolve('./app/javascript/shared/helpers'),
  shared: path.resolve('./app/javascript/shared'),
  survey: path.resolve('./app/javascript/survey'),
  widget: path.resolve('./app/javascript/widget'),
  assets: path.resolve('./app/javascript/dashboard/assets'),
};

export const vueOptions = {
  template: {
    compilerOptions: {
      // `lord-icon` é o custom element do ícone animado (LordIconIcon.vue). Sem
      // declará-lo aqui o compilador Vue o trata como componente, não resolve e
      // o ícone não renderiza.
      isCustomElement: (tag: string) =>
        ['ninja-keys', 'lord-icon'].includes(tag),
    },
  },
};
