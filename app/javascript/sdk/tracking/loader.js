/**
 * Bloco 5.07 (opção **c** do T-C2.0) + 5.08 (T-C2.8) — o CARREGADOR FINO.
 *
 * POR QUE NÃO UM `import()` NORMAL. `vite.lib.config.ts` constrói o SDK com
 * `inlineDynamicImports: true` — é obrigatório, porque o SDK sai como um IIFE único. A
 * consequência, medida: um `import('./index')` estático **não vira chunk**, o Rollup INLINA
 * o módulo dentro do `sdk.js`. "Carregar sob demanda" com import comum entregaria zero
 * economia, e cada byte do coletor cairia sobre o orçamento do arquivo que 100% dos
 * visitantes de todos os sites baixam.
 *
 * O que funciona é um import com URL de RUNTIME: o Rollup não consegue resolvê-la em tempo
 * de build, então ele a deixa passar. O coletor vira um artefato próprio
 * (`public/packs/js/tracking.js`), buscado só quando a inbox tem tracking configurado.
 *
 * O que fica no `sdk.js` é só este arquivo.
 */

/** Caminho do artefato do coletor. Fixo, como o do próprio SDK. */
export const COLLECTOR_PATH = '/packs/js/tracking.js';

/**
 * A inbox tem tracking ativo? Sem isso, nada é buscado — que é o T-C2.8 em uma linha.
 * `test_mode` NÃO conta como configuração: é o modo em que o cliente está conferindo, e
 * ligar o coletor por causa dele seria decidir por ele.
 */
export const hasTrackingConfig = tracking =>
  Boolean(
    tracking &&
      (tracking.ga4_measurement_id ||
        tracking.meta_pixel_id ||
        tracking.google_ads_send_to)
  );

/**
 * Busca o coletor. Devolve `null` — nunca lança — quando não há config, quando o navegador
 * não faz import dinâmico ou quando a rede falha: o chat do cliente não pode depender de
 * uma camada de atribuição ter carregado.
 */
export const loadCollector = async ({ baseUrl, tracking }) => {
  if (!hasTrackingConfig(tracking)) return null;

  try {
    return await import(/* @vite-ignore */ `${baseUrl}${COLLECTOR_PATH}`);
  } catch {
    return null;
  }
};
