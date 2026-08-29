/**
 * BLOCO 3.18 — A REQUISICAO DO RELATORIO DE PRECEDENCIA, MONTADA NUM LUGAR SO.
 *
 * O QUE ESTAVA QUEBRADO
 *
 * `appearanceOverrides.js` chamava `API.post('/api/v1/widget/appearance_overrides', { fields })`.
 * Todo endpoint do widget herda de `Api::V1::Widget::BaseController`, e o
 * `before_action :set_web_widget` (`app/controllers/concerns/website_token_helper.rb:7`) faz
 * `Channel::WebWidget.find_by!(website_token: params[:website_token])`. Sem esse parametro o
 * `find_by!` levanta `RecordNotFound` e a resposta e **404** — MEDIDO, nao suposto. O `.catch`
 * de melhor esforco engolia o 404, o relatorio nunca chegava ao servidor,
 * `additional_attributes['widget_appearance_overrides']` continuava sem produtor e o aviso de
 * override da tela de aparencia (`AppearancePage.vue`) ficava inerte para sempre. Metade do
 * aceite do 3.18 ("...E a tela avisa") estava morta em producao.
 *
 * POR QUE OS OUTROS ENDPOINTS DO WIDGET NAO CAIAM NISSO
 *
 * Eles montam a URL por `endPoints.js`, que cola `buildSearchParamsWithLocale(window.location.search)`
 * — e o `search` do iframe SEMPRE traz o token, porque o `src` e
 * `${baseUrl}/widget?website_token=${websiteToken}` (`sdk/IFrameHelper.js:119-134`). Quem montou o
 * caminho na mao ficou de fora dessa regra sem que nada ficasse vermelho.
 *
 * POR QUE ESTE ARQUIVO NAO IMPORTA NADA
 *
 * E deliberado, e o motivo e o teste. Nesta base tres defeitos seguidos passaram por todos os
 * testes porque o spec do front dublava a requisicao e o request spec dublava o corpo: o front
 * afirmava `post(CAMINHO, { fields })` contra um `API` falso, e o request spec mandava
 * `website_token` **dentro do corpo JSON** — coisa que o widget nunca fez. Os dois lados verdes,
 * a junta morta.
 *
 * Sendo puro e sem `import`, este modulo pode ser EXECUTADO pelo request spec
 * (`spec/controllers/api/v1/widget/appearance_overrides_request_spec.rb` roda ele no `node` e
 * repassa a URL e o corpo que sairem daqui para o Rails de verdade). A requisicao que o teste
 * atravessa deixa de ser uma copia escrita a mao e passa a ser a do produto.
 */

/** O caminho declarado em `config/routes.rb` (`resource :appearance_overrides`). */
export const APPEARANCE_OVERRIDES_PATH = '/api/v1/widget/appearance_overrides';

/**
 * Monta a requisicao, ou devolve `null` quando nao ha o que mandar.
 *
 * `null` nos dois casos em que postar seria pior que calar:
 *
 *  · `fields` que nao e array — "o host nao mediu". Lista VAZIA, essa sim, viaja: e o que apaga
 *    um aviso velho depois de o cliente remover o `chatwootSettings` do site dele.
 *  · `search` sem `website_token` — a requisicao seria um 404 garantido. Devolver `null` troca
 *    uma ida a rede inutil por nada, e e o unico jeito de esse caso ser visivel em teste (o
 *    `.catch` de melhor esforco torna 404 e 204 indistinguiveis para quem chama).
 *
 * Vai so o `website_token`, e nao o `search` inteiro: e o unico parametro que o servidor le
 * (`permitted_params` = `params.permit(:website_token)`), e o `cw_conversation` que tambem mora
 * no `search` e credencial de sessao — nao ha razao para repeti-la numa URL que este endpoint
 * nao usa.
 */
export const buildAppearanceOverridesRequest = ({
  search = '',
  fields,
} = {}) => {
  if (!Array.isArray(fields)) return null;

  const websiteToken = new URLSearchParams(search).get('website_token');
  if (!websiteToken) return null;

  return {
    url: `${APPEARANCE_OVERRIDES_PATH}?website_token=${encodeURIComponent(websiteToken)}`,
    body: { fields },
  };
};

export default { APPEARANCE_OVERRIDES_PATH, buildAppearanceOverridesRequest };
