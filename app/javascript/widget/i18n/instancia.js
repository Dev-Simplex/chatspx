/**
 * A instância do vue-i18n do widget — bloco 2.18.
 *
 * Ela morava dentro de `entrypoints/widget.js`, e enquanto todas as traduções
 * chegavam no first-paint isso bastava. Agora que o idioma é buscado sob
 * demanda, alguém precisa REGISTRAR o pacote que chegou — e `setLocaleMessage`
 * é do objeto do i18n, não de `this.$root.$i18n` (com `legacy: false` o que a
 * instância expõe ali não tem esse método; foi medido em Chromium, com
 * `pageerror: this.$root.$i18n.setLocaleMessage is not a function`).
 *
 * Um módulo só, para que o entrypoint e o `App.vue` falem com a MESMA
 * instância sem que um importe o outro.
 */
import { createI18n } from 'vue-i18n';
import mensagens from './index';

export const i18n = createI18n({
  legacy: false, // https://github.com/intlify/vue-i18n/issues/1902
  locale: 'en',
  messages: mensagens,
});

/**
 * Registra um pacote de tradução já carregado. Sem isto o objeto `mensagens`
 * pode até crescer, mas o vue-i18n não enxerga: ele copia `messages` na
 * criação.
 */
export const registrarLocale = (codigo, pacote) => {
  if (!codigo || !pacote) return;
  i18n.global.setLocaleMessage(codigo, pacote);
};

export default i18n;
