// SUG-02: formulario publico de sugestoes (/sugestoes), sem login e sem store.
import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from '../suggestions/i18n';
import App from '../suggestions/App.vue';

// legacy: false porque o App usa useI18n (Composition API); no modo legado ele quebra ao montar.
const i18n = createI18n({
  legacy: false,
  locale: navigator.language?.toLowerCase().startsWith('pt') ? 'pt_BR' : 'en',
  fallbackLocale: 'en',
  messages,
});

const app = createApp(App);
app.use(i18n);

window.onload = () => {
  app.mount('#app');
};
