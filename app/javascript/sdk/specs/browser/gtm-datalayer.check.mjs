/* eslint-disable no-console -- Verificador de linha de comando: a saída É o resultado. */
/**
 * Bloco 5.22 — a regra **R9** verificada na PORTA DE ENTRADA, em navegador real.
 *
 * O aceite do bloco diz: *"o snippet do GTM não sobrescreve `window.dataLayer` do cliente"*. Essa
 * frase tem duas metades, e só uma delas é verificável lendo texto:
 *
 *   · o TRECHO que o servidor gera não menciona `dataLayer` — isso o spec do documento cobra
 *     (`instalacaoPorPlataforma.spec.js`), lendo `web_widget.rb`;
 *   · o SDK que o trecho carrega **também** não pode sobrescrevê-lo — e isso só se vê rodando o
 *     `sdk.js` de verdade, num documento de verdade, sobre um `dataLayer` que já existe.
 *
 * A segunda metade é este arquivo. Ele carrega o **artefato construído** e verifica a preservação
 * por IDENTIDADE (`===`) — que é a diferença entre estender e substituir, e é exatamente o que um
 * mock não consegue perder.
 *
 * E verifica a garantia que o documento usa para convencer o integrador a chamar o SDK de dentro
 * de uma tag: **nada lança de forma síncrona**. No GTM as tags de um mesmo acionamento rodam em
 * sequência, no mesmo contexto; uma exceção numa delas interrompe as SEGUINTES, e o site do
 * cliente para de medir com a culpa caindo no chat. Aqui a sequência é simulada literalmente.
 *
 *   npx vite build --config vite.lib.config.ts
 *   node app/javascript/sdk/specs/browser/gtm-datalayer.check.mjs
 *
 * ⚠️ Servidor em porta EFÊMERA (`listen(0)`) — as portas 3038/3999/8899 estão sob tranca do
 * coordenador. Sai 0/1/2 (2 = não conseguiu medir).
 */
import { existsSync, readFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { chromium } from 'playwright';

const SDK = path.join(process.cwd(), 'public/packs/js/sdk.js');

if (!existsSync(SDK)) {
  console.error(
    `[5.22] artefato ausente: ${SDK}\n` +
      'Rode `npx vite build --config vite.lib.config.ts` antes.'
  );
  process.exit(2);
}

const results = [];
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}` +
      (ok
        ? ''
        : `\n        esperado=${JSON.stringify(expected)}  recebido=${JSON.stringify(actual)}`)
  );
};

/**
 * O site do cliente ANTES de nós: o `gtm.js` já rodou, o `dataLayer` já tem coisas dentro e o
 * `gtag` já existe. É a página de quem mede o próprio site há anos — e é ela que a regra R9
 * protege.
 */
const PAGINA = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>site do cliente</title>
<script>
  window.dataLayer = [{ event: 'gtm.js' }, { event: 'promocao_vista' }];
  window.gtagDoCliente = function () { window.gtagChamadas.push([].slice.call(arguments)); };
  window.gtagChamadas = [];
  window.gtag = window.gtagDoCliente;
</script>
</head><body><h1>site do cliente</h1></body></html>`;

const servidor = http.createServer((req, res) => {
  if (req.url.startsWith('/packs/js/sdk.js')) {
    res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    res.end(readFileSync(SDK));
    return;
  }
  if (req.url.startsWith('/widget')) {
    // O painel do widget. Aqui ele não importa: o que se mede é o documento do HOST.
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end('<!doctype html><html><body>painel</body></html>');
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(PAGINA);
});

await new Promise(resolve => {
  servidor.listen(0, '127.0.0.1', resolve);
});
const base = `http://127.0.0.1:${servidor.address().port}`;

const browser = await chromium.launch();
const pagina = await browser.newPage();

const mensagens = [];
const erros = [];
pagina.on('console', m => mensagens.push(`${m.type()}: ${m.text()}`));
pagina.on('pageerror', e => erros.push(e.message));

await pagina.goto(base, { waitUntil: 'networkidle' });

console.log(
  '\n5.22 — o SDK sobre o `dataLayer` do cliente, em Chromium real\n'
);

const resultado = await pagina.evaluate(async origem => {
  const dataLayerAntes = window.dataLayer;
  const gtagAntes = window.gtag;
  const filaAntes = window.dataLayer.length;

  // É EXATAMENTE o que o trecho do servidor faz: injeta o `sdk.js` e chama `run`.
  await new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = `${origem}/packs/js/sdk.js`;
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });

  window.chatwootSDK.run({ websiteToken: 'tok-de-teste', baseUrl: origem });
  await new Promise(r => {
    setTimeout(r, 400);
  });

  // ── O CAMINHO QUE REALMENTE TOCA O `dataLayer` DO CLIENTE ──────────────────────────────
  //
  // Boot sozinho não basta, e isto foi DESCOBERTO POR SABOTAGEM: com `window.dataLayer = []`
  // plantado no `consent.js`, este arquivo passava verde — porque nada no boot chega a publicar
  // no `dataLayer`. Quem publica é o Consent Mode (`setConsent`/`updateConsent`, bloco 5.09) e a
  // ponte de tags. Um verificador que não exercita o caminho perigoso não protege dele.
  //
  // SEM `await`, e a razão é um achado desta trilha: `setConsent` passa pela FILA PRÉ-BOOT
  // (`preBootQueue`), que só drena quando o painel avisa que carregou. Aqui o painel é um HTML
  // estático, então a `Promise` fica pendente para sempre e um `await` travaria o verificador.
  // O que se mede aqui é o que NÃO depende do painel: a chamada não lança e o `dataLayer` do
  // cliente continua sendo o mesmo array. A publicação em si é medida em
  // `sdk/tracking/specs/browser/ponte-de-tags.check.mjs`, que exercita a ponte direto — e lá a
  // sabotagem "reatribui o dataLayer" É pega (6 asserções vermelhas).
  let consentRejeitou = null;
  window.$chatwoot.setConsent({ analytics_storage: 'granted' }).catch(e => {
    consentRejeitou = e.message;
  });
  await new Promise(r => {
    setTimeout(r, 200);
  });

  // ── A SEQUÊNCIA DE TAGS DO GTM ────────────────────────────────────────────────────────
  // Três tags do mesmo acionamento, no mesmo contexto. A do meio chama o SDK com argumento
  // inválido. No GTM, um `throw` ali impede a terceira de rodar — e o site do cliente para de
  // medir. Aqui a terceira TEM de rodar.
  const tagsQueRodaram = [];
  let excecaoSincrona = null;
  try {
    tagsQueRodaram.push('tag-1');
    window.$chatwoot.track('nome_invalido_sem_prefixo', { a: 1 });
    tagsQueRodaram.push('tag-2');
    window.$chatwoot.setUser({}, {});
    tagsQueRodaram.push('tag-3');
  } catch (e) {
    excecaoSincrona = e.message;
  }

  await new Promise(r => {
    setTimeout(r, 100);
  });

  return {
    consentRejeitou,
    dataLayerPreservado: window.dataLayer === dataLayerAntes,
    gtagPreservado: window.gtag === gtagAntes,
    filaDoCliente: window.dataLayer.slice(0, filaAntes).map(e => e && e.event),
    chatwootExiste: typeof window.$chatwoot === 'object',
    tagsQueRodaram,
    excecaoSincrona,
  };
}, base);

console.log(
  '· o `dataLayer` e o `gtag` do cliente sobrevivem ao SDK (R9 / RC2)'
);
check('o SDK subiu de verdade nesta página', resultado.chatwootExiste, true);
check(
  '`window.dataLayer` é o MESMO array de antes',
  resultado.dataLayerPreservado,
  true
);
check(
  '`window.gtag` é a MESMA função de antes',
  resultado.gtagPreservado,
  true
);
check(
  'a fila que o cliente já tinha continua lá, na ordem',
  resultado.filaDoCliente,
  ['gtm.js', 'promocao_vista']
);
// `setConsent` NÃO pode rejeitar: até esta trilha ele rejeitava SEMPRE, com
// `TypeError: validar is not a function`, e o consentimento nunca era publicado.
check(
  '`setConsent` não rejeita mais na chamada',
  resultado.consentRejeitou,
  null
);

console.log('\n· a sequência de tags do GTM não é interrompida');
check(
  'as três tags rodaram — inclusive a que vem DEPOIS da chamada inválida',
  resultado.tagsQueRodaram,
  ['tag-1', 'tag-2', 'tag-3']
);
check('nenhuma exceção síncrona escapou', resultado.excecaoSincrona, null);
check('nenhum erro não capturado na página', erros, []);

console.log('\n· o erro do integrador aparece, mas no lugar certo');
check(
  'o console recebeu o erro do argumento inválido — o SDK não é mudo',
  mensagens.some(m => m.startsWith('error:') && m.includes('[chatwoot]')),
  true
);

await browser.close();
servidor.close();

const falhas = results.filter(r => !r.ok);
console.log(
  falhas.length
    ? `\n${falhas.length} de ${results.length} asserções FALHARAM.\n`
    : `\n${results.length} asserções passaram em navegador real.\n`
);
process.exit(falhas.length ? 1 : 0);
