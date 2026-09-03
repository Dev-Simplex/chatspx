/**
 * Bloco 5.18 — `data-*` de CONFIGURAÇÃO no snippet, nunca identidade.
 *
 * A regra em uma frase: **configuração viaja por qualquer via; identidade e credencial, só pela
 * API JS.**
 *
 * POR QUE A DISTINCAO E DURA. O snippet e HTML: ele aparece no view-source, entra em cache de CDN,
 * fica no historico do navegador e e copiado entre paginas por quem cuida do site, nao por quem
 * cuida de dados. Configuracao ali e inofensiva — a posicao da bolha e publica de qualquer jeito.
 * Identidade nao: `data-email` num template de e-commerce vaza o cliente para qualquer um que veja
 * a fonte da pagina, e `data-identifier-hash` publica a credencial que existe justamente para
 * provar que aquele visitante e ele mesmo.
 *
 * A recusa e ALTA E VISIVEL, com aviso no console nomeando a chave: recusa silenciosa faria o
 * integrador achar que configurou e seguir em frente.
 */

// As chaves de configuracao que o `run()` consome. A lista e fechada de proposito: chave nova aqui
// e uma decisao, nao um efeito colateral de alguem ter escrito um `data-` novo no snippet.
export const CONFIG_KEYS = [
  'locale',
  'position',
  'type',
  'launcherTitle',
  'hideMessageBubble',
  'showPopoutButton',
  'showUnreadMessagesDialog',
  'widgetStyle',
  'darkMode',
  'welcomeTitle',
  'welcomeDescription',
  'availableMessage',
  'unavailableMessage',
  'enableFileUpload',
  'useBrowserLanguage',
  'baseDomain',
];

// Identidade e credencial. Sao recusadas por NOME, e o nome e comparado em minusculas sem
// separadores — `data-identifier-hash`, `identifierHash` e `IDENTIFIER_HASH` sao a mesma coisa.
export const IDENTITY_KEYS = [
  'identifier',
  'identifierhash',
  'email',
  'name',
  'phonenumber',
  'phone',
  'avatarurl',
  'user',
  'userid',
  'contact',
  'contactid',
  'customattributes',
  'companyname',
  'signedupat',
];

// Qualquer coisa com cara de segredo, alem da identidade. Mesma familia da lista do bloco 5.01, do
// lado do navegador: o snippet e ainda mais publico que a config da inbox.
// `apiKey` vira `api_key` na normalizacao, entao o padrao precisa das DUAS grafias — foi o teste
// deste bloco que pegou a falta, com `apiKey` e `privateKey` passando batido.
const SECRET_PATTERN =
  /(^|_)(token|secret|password|passwd|pwd|credential|credentials|api_key|apikey|private_key|privatekey|auth|authorization|signature|bearer)($|_)/;

const canonical = key =>
  String(key)
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toLowerCase();

const flat = key => canonical(key).replace(/_/g, '');

export const isIdentityKey = key => IDENTITY_KEYS.includes(flat(key));

export const isSecretKey = key => SECRET_PATTERN.test(canonical(key));

// `data-hide-message-bubble="true"` chega como a string "true". Sem isto, toda flag booleana do
// snippet seria verdadeira — inclusive `="false"`, que e a forma que o integrador usa para desligar.
const coerce = value => {
  if (value === 'true') return true;
  if (value === 'false') return false;

  return value;
};

/**
 * Lê o `dataset` do snippet e devolve `{ config, rejected }`.
 *
 * `rejected` nao e detalhe de log: e o que o chamador usa para avisar no console. Devolver so a
 * config faria a recusa acontecer em silencio, que e o defeito que este bloco existe para evitar.
 */
export const readSnippetConfig = (dataset = {}) => {
  const config = {};
  const rejected = [];

  Object.keys(dataset).forEach(key => {
    if (isIdentityKey(key) || isSecretKey(key)) {
      rejected.push(key);
      return;
    }
    if (!CONFIG_KEYS.includes(key)) return;

    config[key] = coerce(dataset[key]);
  });

  return { config, rejected };
};

/**
 * Precedencia declarada: `window.chatwootSettings` VENCE o `data-*`.
 *
 * A via explicita em JavaScript e a que o dono da integracao controla; o snippet costuma ser
 * colado por outra pessoa, as vezes por um gerenciador de tags. Quando as duas dizem coisas
 * diferentes, a que o integrador escreveu por ultimo e a que ele consegue depurar deve vencer —
 * e a inversa produziria "mudei no codigo e nao mudou no site", sem nada no console.
 */
export const mergeSnippetConfig = (settings = {}, dataset = {}) => {
  const { config, rejected } = readSnippetConfig(dataset);

  return { settings: { ...config, ...settings }, rejected };
};
