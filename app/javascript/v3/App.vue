<script>
import SnackbarContainer from './components/SnackBar/Container.vue';

export default {
  components: { SnackbarContainer },
  data() {
    return { theme: 'light' };
  },
  mounted() {
    this.setColorTheme();
    this.listenToThemeChanges();
    this.setLocale('pt_BR');
  },
  methods: {
    setColorTheme() {
      if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
        this.theme = 'dark';
        document.documentElement.classList.add('dark');
      } else {
        this.theme = 'light';
        document.documentElement.classList.remove('dark');
      }
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');

      mql.onchange = e => {
        if (e.matches) {
          this.theme = 'dark';
          document.documentElement.classList.add('dark');
        } else {
          this.theme = 'light';
          document.documentElement.classList.remove('dark');
        }
      };
    },
    setLocale(locale) {
      this.$root.$i18n.locale = locale;
    },
  },
};
</script>

<template>
  <div class="flex flex-col min-h-screen w-full antialiased justify-between" :class="theme">
    <div class="flex-1 flex flex-col">
      <router-view class="flex-1" />
      <SnackbarContainer />
    </div>
    <!-- Rodapé estilizado grudado no fim, nunca cria rolagem -->
    <div class="w-full flex justify-center items-center select-none py-6">
      <span
        class="rounded-md px-4 py-1 text-base font-light tracking-wide shadow-lg"
        style="background: rgba(32,32,32,0.86); color: #e0e0e0;"
      >
        Desenvolvido por
        <a
          href="https://simplexsolucoes.com.br/"
          target="_blank"
          rel="noopener noreferrer"
          class="font-bold underline text-blue-500 hover:text-blue-400 transition"
          style="margin-left: 4px;"
        >Simplex</a>
      </span>
    </div>
  </div>
</template>


<style lang="scss">
@tailwind base;
@tailwind components;
@tailwind utilities;

@import '../dashboard/assets/scss/next-colors';

// Corrige fundo, zera margin/padding, e previne rolagem
html, body {
  min-height: 100%;
  height: 100%;
  width: 100%;
  margin: 0;
  padding: 0;
  background: #181818 !important; // Mesmo tom do seu app
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
    Oxygen-Sans, Ubuntu, Cantarell, 'Helvetica Neue', sans-serif;
  overflow-x: hidden;
}

input,
select {
  outline: none;
}

.text-link {
  @apply text-n-brand font-medium hover:text-n-teal-10;
}

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
