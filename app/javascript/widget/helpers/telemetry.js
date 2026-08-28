/**
 * Telemetria de erro do widget — bloco 2.13.
 *
 * O QUE EXISTIA: ~11 `catch (error) { // Ignore error }` espalhados pelo widget
 * e ZERO observabilidade. Quando o widget quebrava no site de um cliente,
 * ninguém ficava sabendo — nem nós, nem ele. O primeiro sinal era o cliente
 * reclamando que "o chat sumiu".
 *
 * ── POR QUE NÃO O SDK DO SENTRY ──────────────────────────────────────────────
 *
 * O aceite do bloco 2.18 exige `window.__SENTRY__` **undefined** dentro do
 * iframe. Não é capricho: o SDK do Sentry sozinho pesa mais que o orçamento
 * inteiro de JS do widget (≤ 150 KB gzip), e o widget é baixado por visitante
 * em rede móvel no site de terceiro. Então a telemetria daqui é um POST cru —
 * sem SDK, sem instrumentação global, sem monkey-patch de `fetch`.
 *
 * ── POR QUE PARA O NOSSO SERVIDOR, E NÃO DIRETO PARA O GLITCHTIP ─────────────
 *
 * Três razões concretas:
 *
 *  1. O documento do widget é servido pelo NOSSO domínio, então este POST é
 *     same-origin. Um POST direto ao GlitchTip seria cross-origin e morreria na
 *     `connect-src` de qualquer cliente com CSP apertada — justamente os
 *     clientes cujos problemas mais queremos ver.
 *  2. `SENTRY_DSN` já está configurado por VM na frota. Mandar do navegador
 *     exigiria publicar um DSN no HTML de cada widget e configurá-lo de novo.
 *  3. O servidor faz a SEGUNDA raspagem de PII. Confiar só no cliente para
 *     remover dado pessoal é confiar em código que roda na máquina de outra
 *     pessoa.
 *
 * ── O CONTRATO DE PII ────────────────────────────────────────────────────────
 *
 * O envelope tem uma lista FECHADA de chaves. Não existe "…resto": um objeto de
 * contexto que alguém passe com a mensagem do visitante dentro não tem por onde
 * escapar. Ver `CHAVES_DO_ENVELOPE` e o teste que as congela.
 */

const ENDPOINT = '/api/v1/widget/telemetry';

// Teto por sessão. Um erro dentro de um laço de render viraria milhares de
// POSTs saindo do site do cliente, e o widget passaria a ser o problema de
// desempenho dele.
const MAX_POR_SESSAO = 10;

const LIMITE_MENSAGEM = 1000;
const LIMITE_PILHA = 4000;

let enviadosNestaSessao = 0;
const jaVistos = new Set();

// ─────────────────────────────────────────────────────────────────────────────
// Raspagem de PII
//
// A ordem importa: credencial ANTES de e-mail (um JWT pode conter algo que
// pareça e-mail), e documento ANTES de telefone (CPF e telefone competem pelos
// mesmos dígitos). Trocar a ordem muda o resultado, e há teste para cada caso.
// ─────────────────────────────────────────────────────────────────────────────
const PADROES = [
  // `Bearer <algo>`, `token=<algo>` e JWT solto (três segmentos base64url).
  [/\b[Bb]earer\s+[\w\-.=]+/g, '[credencial]'],
  [/\beyJ[\w-]*\.[\w-]+\.[\w-]+/g, '[credencial]'],
  [
    /\b(token|secret|password|senha|api[_-]?key)=[^\s&;"']+/gi,
    '$1=[credencial]',
  ],
  // CNPJ antes de CPF: o CNPJ contém uma sequência que casa com CPF.
  [/\b\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}\b/g, '[documento]'],
  [/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/g, '[documento]'],
  [/\b\d{16}\b/g, '[documento]'],
  [/\b\d{4}[\s-]\d{4}[\s-]\d{4}[\s-]\d{4}\b/g, '[documento]'],
  [/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[email]'],
  // Telefone: exige DDI ou separador, para não engolir "linha 1234567890" de
  // uma pilha de chamada. O primeiro padrão é deliberadamente frouxo no meio
  // (`[\d\s.-]`) porque a diagramação varia por país — `+55 11 98765-4321` e
  // `+1-415-555-0132` não cabem no mesmo formato rígido, e errar para o lado de
  // raspar demais é o lado certo de errar aqui.
  [/\+\d[\d\s.-]{7,17}\d/g, '[telefone]'],
  [/\(?\b\d{2}\)?[\s-]\d{4,5}-\d{4}\b/g, '[telefone]'],
];

const raspaTexto = texto =>
  PADROES.reduce(
    (parcial, [padrao, substituto]) => parcial.replace(padrao, substituto),
    texto
  );

/**
 * Remove PII de qualquer valor, atravessando estrutura aninhada.
 * Números, booleanos, `null` e `undefined` passam intactos.
 */
export const scrubPii = (valor, vistos = new WeakSet()) => {
  if (typeof valor === 'string') return raspaTexto(valor);
  if (valor === null || typeof valor !== 'object') return valor;

  // Ciclo: um objeto de contexto que referencie a si mesmo não pode travar o
  // reporter — ele roda dentro de `catch`, e travar ali é pior que o erro.
  if (vistos.has(valor)) return '[ciclo]';
  vistos.add(valor);

  if (Array.isArray(valor)) return valor.map(item => scrubPii(item, vistos));

  return Object.fromEntries(
    Object.entries(valor).map(([chave, item]) => [
      chave,
      scrubPii(item, vistos),
    ])
  );
};

// O reticências CONTA para o limite: `slice(0, limite)` mais o caractere daria
// `limite + 1`, e um teto que estoura por um não é teto.
const trunca = (texto, limite) =>
  typeof texto === 'string' && texto.length > limite
    ? `${texto.slice(0, limite - 1)}…`
    : texto;

// Lista FECHADA. É o que impede um contexto descuidado de carregar a conversa
// do visitante para dentro de um relatório de erro.
export const CHAVES_DO_ENVELOPE = [
  'name',
  'message',
  'stack',
  'url',
  'release',
  'context',
  'website_token',
];

/**
 * @param {Error} erro
 * @param {Object} contexto  só `origem` e chaves de diagnóstico; nunca conteúdo
 * @param {Location} localizacao  injetável para teste
 */
export const buildErrorPayload = (
  erro = {},
  contexto = {},
  localizacao = typeof window === 'undefined' ? {} : window.location
) => {
  // `split('?')[0]`: query string de site de terceiro carrega `?email=`,
  // `?token=` e `?cpf=` com frequência desconfortável, e o caminho já basta
  // para saber onde o erro aconteceu.
  const url = String(localizacao?.href ?? '').split('?')[0];

  return {
    name: scrubPii(erro.name ?? 'Error'),
    message: trunca(scrubPii(String(erro.message ?? '')), LIMITE_MENSAGEM),
    stack: trunca(scrubPii(String(erro.stack ?? '')), LIMITE_PILHA),
    url: scrubPii(url),
    release: window.chatwootWebChannel?.release ?? null,
    // Só `origem` atravessa do contexto — ver o comentário de
    // `CHAVES_DO_ENVELOPE`. Qualquer outra chave é descartada aqui.
    context: { origem: scrubPii(contexto.origem ?? 'desconhecida') },
    website_token: window.chatwootWebChannel?.websiteToken ?? null,
  };
};

const chaveDeDeduplicacao = payload =>
  `${payload.name}|${payload.message}|${payload.context.origem}`;

/**
 * Registra um erro. NUNCA lança e NUNCA rejeita — este código roda dentro de
 * `catch`, e uma falha aqui transformaria um erro registrado num erro não
 * tratado, que é o oposto do que o bloco faz.
 */
export const reportWidgetError = async (erro, contexto = {}) => {
  try {
    if (enviadosNestaSessao >= MAX_POR_SESSAO) return;

    const payload = buildErrorPayload(erro, contexto);
    if (!payload.website_token) return;

    const chave = chaveDeDeduplicacao(payload);
    if (jaVistos.has(chave)) return;
    jaVistos.add(chave);
    enviadosNestaSessao += 1;

    // `keepalive` para o relatório sobreviver ao unload — boa parte dos erros
    // acontece justamente quando a aba está fechando.
    const resposta = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      keepalive: true,
    });

    // DRENAR A RESPOSTA NÃO É ZELO, É O ACEITE. Sem esta linha o Chromium
    // cancela o corpo que ninguém leu e registra um `net::ERR_ABORTED`
    // [MEDIDO em Chromium 145: 40 ms DEPOIS do 204, com a página ainda viva —
    // não é artefato de teardown]. Nada chega ao `window.onerror` do site do
    // cliente, mas a aba Network dele passa a mostrar a NOSSA telemetria em
    // vermelho, como requisição falhada — dez vezes seguidas no cenário do
    // teto por sessão. O aceite do bloco é «nada vaza para o site do cliente»,
    // e dez linhas vermelhas com o nosso endpoint no devtools do cliente é
    // exatamente o que ele existe para não acontecer.
    //
    // Encadeamento opcional porque o dublê de `fetch` dos testes em jsdom não
    // é um `Response` de verdade: aqui o que se quer é «se veio corpo, drene»,
    // não «assuma que veio».
    await resposta?.text?.();
  } catch {
    // Engolido de propósito, e este é o único `catch` vazio legítimo do widget:
    // é o fundo do poço da observabilidade. Reportar a falha do reporter pelo
    // próprio reporter seria recursão.
  }
};

// Só para teste: zera o teto e a deduplicação entre exemplos. O prefixo `__`
// marca que isto não é API do módulo — nenhum código de produção deve chamá-la,
// e um nome comum tornaria isso indistinguível das outras exportações.
// eslint-disable-next-line no-underscore-dangle
export const __resetTelemetryForTests = () => {
  enviadosNestaSessao = 0;
  jaVistos.clear();
};

export default { reportWidgetError, scrubPii, buildErrorPayload };
