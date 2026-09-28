// SUG-02: formulario publico de sugestoes (/sugestoes), sem login e sem store.
import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from '../suggestions/i18n';
import App from '../suggestions/App.vue';

const i18n = createI18n({
  locale: navigator.language?.toLowerCase().startsWith('pt') ? 'pt_BR' : 'en',
  fallbackLocale: 'en',
  messages,
});

const app = createApp(App);
app.use(i18n);

window.onload = () => {
  app.mount('#app');
};
