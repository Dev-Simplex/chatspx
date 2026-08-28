import { getBubbleView, getDarkMode, getWidgetStyle } from './settingsHelper';

/**
 * BLOCO 3.18 — A REGRA DE PRECEDENCIA, do lado do host.
 *
 * A regra em uma frase: **o banco e o padrao, o `chatwootSettings` do site
 * sobrescreve, e a tela declara que houve override.**
 *
 * O QUE ESTAVA QUEBRADO, E POR QUE NAO APARECIA EM TESTE NENHUM
 *
 * O schema de `widget_appearance`, os 422, a persistencia multi-admin e a
 * entrega nos dois montadores ja existiam. O que nao existia era LEITOR: o
 * `entrypoints/sdk.js` montava `window.$chatwoot` inteiro a partir de
 * `chatwootSettings`, com fallback CRAVADO no proprio arquivo
 * (`position: … === 'left' ? 'left' : 'right'`, `widgetStyle: … || 'standard'`).
 * O administrador gravava `position: left`, o `widgetAppearance` viajava no
 * `channelConfig` ate o host — e o unico consumidor dele lia `launcher_icon`.
 * O widget continuava a direita, e nada ficava vermelho porque nenhum dos dois
 * lados estava errado sozinho: faltava a junta.
 *
 * A TABELA E UMA SO, E ELA E ESPELHO
 *
 * `SITE_KEY_BY_FIELD` espelha `OVERRIDABLE_BY_SITE` de
 * `app/models/concerns/widget_appearance_schema.rb`, e
 * `specs/precedenciaAparencia.spec.js` LE o arquivo Ruby e falha nomeando o
 * campo que divergir. Vocabulario comum entre backend, SDK e tela: sem isso, o
 * servidor publica `panel_style`, o SDK procura `widgetStyle` e a tela avisa
 * sobre um terceiro nome.
 *
 * Coincidencia util, e ela e verificada no spec: o nome que o site usa em
 * `chatwootSettings` e o MESMO nome da propriedade em `window.$chatwoot`. Por
 * isso uma tabela so responde as duas perguntas — "o site mandou?" e "onde eu
 * escrevo o valor do banco?".
 *
 * SOBRE O TAMANHO DESTE ARQUIVO. Ele entra no `sdk.js`, que tem teto CRU de
 * 40.000 B (A13) e e baixado por 100% dos visitantes de todos os sites de todos
 * os clientes. Comentario nao custa byte nenhum (o terser os remove); CODIGO
 * custa. Por isso nao ha aqui acumulador de campos alterados, nem tabela
 * repetida, nem verbo que ninguem chama — cada um deles foi medido e cortado.
 */
export const SITE_KEY_BY_FIELD = {
  theme: 'darkMode',
  position: 'position',
  launcher_type: 'type',
  launcher_text: 'launcherTitle',
  hide_bubble: 'hideMessageBubble',
  panel_style: 'widgetStyle',
};

// O teto do offset e o mesmo `MAX_OFFSET` do schema (200 px), e o spec compara
// os dois numeros. Repetido aqui porque estes valores acabam num `style`
// inline: o servidor recusa 500 com 422, mas o host nao pode DEPENDER disso
// para nao escrever `left: 9999px` no site do cliente — e a mesma cautela que
// `applyWidgetTokens` (1.03) tem com a cor que chega pela ponte.
export const MAX_OFFSET = 200;

/**
 * Um normalizador por campo, e nenhum deles inventa valor.
 *
 * Reusam `settingsHelper`, que e o mesmo vocabulario que o `entrypoints/sdk.js`
 * aplica ao valor do site: se o banco e o site passam pela MESMA normalizacao,
 * "o site venceu" e uma decisao sobre a fonte, nunca sobre a forma.
 */
const NORMALIZE = {
  theme: getDarkMode,
  position: valor => (valor === 'left' ? 'left' : 'right'),
  launcher_type: getBubbleView,
  launcher_text: valor => (typeof valor === 'string' ? valor : ''),
  hide_bubble: valor => valor === true,
  panel_style: getWidgetStyle,
};

const CAMPOS = Object.keys(SITE_KEY_BY_FIELD);

/**
 * Quais campos de `widget_appearance` o site esta sobrescrevendo AGORA.
 *
 * PRESENCA, NAO VERACIDADE. `hideMessageBubble: false` escrito no snippet E um
 * override: o site disse "nao esconda", e se o banco disser "esconda" quem vence
 * e o site — e a tela precisa avisar. Testar por `||` (que era o que o
 * `entrypoints/sdk.js` fazia) trataria o `false` explicito como ausencia e o
 * aviso nunca apareceria justamente no caso em que as duas fontes discordam.
 *
 * `!= null` e deliberado e cobre os DOIS jeitos de a chave nao ser escolha:
 * ausente (`undefined`) e `chatwootSettings.position = null`, que e sobra de
 * template, nao decisao do integrador.
 */
export const camposSobrescritosPeloSite = (settings = {}) =>
  // eslint-disable-next-line eqeqeq
  CAMPOS.filter(campo => (settings || {})[SITE_KEY_BY_FIELD[campo]] != null);

/**
 * O BANCO VIRA PADRAO — e so onde o site nao falou.
 *
 * Roda no `loaded`, que e quando o `channelConfig` do servidor atravessa a
 * ponte: e o primeiro instante em que o host CONHECE o que esta gravado. Antes
 * disso `window.$chatwoot` carrega os valores do site (ou os de fabrica), que e
 * o que o `createFrame` ja usou — por isso quem chama tem de reaplicar as
 * classes do holder depois.
 *
 * A precedencia e por CAMPO, nunca por fonte: um `chatwootSettings` com uma
 * chave nao pode desligar a configuracao inteira da inbox.
 */
export const aplicarPadraoDoBanco = ({
  appearance = {},
  overrides = [],
  alvo,
}) => {
  CAMPOS.forEach(campo => {
    const valor = (appearance || {})[campo];
    // eslint-disable-next-line eqeqeq
    if (overrides.includes(campo) || valor == null) return;
    alvo[SITE_KEY_BY_FIELD[campo]] = NORMALIZE[campo](valor);
  });
};

/**
 * `offset_x` / `offset_y`: os dois campos que o site NAO pode sobrescrever.
 *
 * Eles nao estao em `OVERRIDABLE_BY_SITE` — nao ha chave de `chatwootSettings`
 * que os defina —, entao aqui o banco nao disputa com ninguem: ou ele manda, ou
 * o campo continua sendo write-only, que era o estado medido. Viram custom
 * properties porque a distancia da quina esta em varias regras do `SDK_CSS`, e
 * um `calc()` com `var(…, 0px)` deixa TODAS elas com o comportamento de hoje
 * enquanto o valor for 0.
 *
 * Devolve `null` quando nao ha o que aplicar, para nao escrever
 * `--w-offset-x: 0px` em quem nunca configurou nada.
 */
export const deslocamentoDoBanco = (appearance = {}) => {
  // `Math.trunc(...) || 0` faz as duas coisas que impedem este valor de virar
  // `left: NaNpx` no site do cliente: trunca para inteiro (o schema so aceita
  // inteiro) e transforma em 0 tanto o ausente quanto o que nao e numero. O
  // clamp seguinte e o mesmo teto do servidor, reaplicado aqui porque o
  // resultado acaba num `style` inline.
  const px = valor =>
    `${Math.min(Math.max(Math.trunc(valor) || 0, 0), MAX_OFFSET)}px`;

  const x = px(appearance.offset_x);
  const y = px(appearance.offset_y);

  return x === '0px' && y === '0px'
    ? null
    : { '--w-offset-x': x, '--w-offset-y': y };
};
