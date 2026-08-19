/**
 * camelCase de chaves para o widget — bloco 2.18.
 *
 * O gêmeo do dashboard (`dashboard/composables/useTransformKeys.js`) faz a
 * mesma conversão, mas importa `@sentry/vue` para reportar a falha do
 * `camelcase-keys`. Esse import é ESTÁTICO, e era o único caminho por onde o
 * SDK do Sentry entrava no grafo de first-paint do widget: 31.261 B gzip para
 * um `try/catch` — medido, não estimado.
 *
 * Um arquivo só para não importar de `dashboard/` no widget. O aceite do 2.18
 * exige `window.__SENTRY__` UNDEFINED dentro do iframe, e o 2.13 já deixou
 * pronto o canal de erro que o widget usa no lugar: um POST cru para o nosso
 * servidor, sem SDK. Ver o cabeçalho de `widget/helpers/telemetry.js`.
 */
import { unref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { reportWidgetError } from 'widget/helpers/telemetry';

/**
 * Converte as chaves de um objeto/array para camelCase.
 * @param {Object|Array|import('vue').Ref<Object|Array>} payload
 * @param {Object} [options]
 * @param {boolean} [options.deep=false]
 * @returns {Object|Array} o payload convertido, ou o original se falhar
 */
export function useCamelCase(payload, options) {
  try {
    return camelcaseKeys(unref(payload), options);
  } catch (erro) {
    // Devolver o payload cru é o mesmo contorno do dashboard: uma chave que não
    // converteu não pode derrubar a tela do visitante.
    reportWidgetError(erro, { op: 'camelCase' });
    return payload;
  }
}
