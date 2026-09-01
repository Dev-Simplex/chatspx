/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco.
   Não é log esquecido em código de produção, que é o que a regra pega. */
/**
 * ACEITE DO BLOCO 2.03, medido em Chromium — nunca deduzido do código.
 *
 *   `boxShadow === 'none'`; contraste ≥ 4,5:1 nos DOIS temas,
 *   nas DUAS cores de teste.
 *
 * ── Por que este arquivo existe, e não um spec de jsdom ─────────────────────
 *
 * Porque as duas metades do aceite são de valor COMPUTADO, e jsdom não computa
 * nenhuma das duas: ele não resolve `var(--w-brand)`, não aplica cascade de
 * `@layer`, e devolve a string que você escreveu. Um teste de classe — "a bolha
 * tem `bg-w-brand`" — passa com o widget preto no branco.
 *
 * As duas armadilhas concretas que este arquivo pega, e que uma asserção de
 * classe deixa passar:
 *
 *   1. `@apply shadow-none` do Tailwind NÃO computa `none`. Ele emite a cadeia
 *      `var(--tw-ring-offset-shadow,0 0 #0000), …, 0 0 #0000`, que o navegador
 *      devolve como `rgba(0, 0, 0, 0) 0px 0px 0px 0px`. Era assim que o
 *      primitivo `widget/ui/WBubble.vue` estava — com um comentário citando
 *      este mesmo aceite ao lado.
 *   2. O contraste da bolha do visitante depende de `--w-on-brand`, que é
 *      calculado no SERVIDOR por luminância WCAG. Só medindo a cor pintada dá
 *      para saber se a conta chegou.
 *
 * ── De onde vêm os tokens das duas cores de teste ───────────────────────────
 *
 * Do `WidgetTokens` em Ruby, executado de verdade — não de uma cópia da fórmula
 * escrita aqui. `app/services/widget_tokens.rb` não depende de Rails (é
 * aritmética sobre três inteiros), então `ruby -r` o carrega direto e devolve
 * exatamente o `<style>` que `show.html.erb` emite. Duplicar a fórmula em JS
 * seria reintroduzir o defeito que o bloco 1.02 corrigiu: duas contas de
 * contraste livres para divergir.
 *
 *   bin/vite build --force        # gera public/vite/assets/widget-*.css
 *   node app/javascript/widget/components/specs/browser/bubble-geometry.check.mjs
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright';
import { brandTokens } from '../../../../dashboard/routes/dashboard/settings/inbox/widget/composables/useContrast.js';

// As duas cores de teste do aceite. `#009CE0` é azul claro e `#2DC46F` é o
// verde da casa: as duas caem do MESMO lado do limiar de luminância (as duas
// pedem texto preto), mas com razões bem diferentes — 6,83:1 e 9,24:1 —, e é
// por isso que medir as duas não é redundância.
const CORES = ['#009CE0', '#2DC46F'];
const TEMAS = ['light', 'dark'];
const ALVO_CONTRASTE = 4.5;

const resultados = [];
const ok = (nome, condicao, detalhe) => {
  resultados.push({ nome, ok: condicao });
  console.log(`${condicao ? '  ok  ' : ' FAIL '} ${nome}\n        ${detalhe}`);
};
const igual = (nome, medido, esperado) =>
  ok(nome, medido === esperado, `esperado=${esperado}  recebido=${medido}`);
const aoMenos = (nome, medido, minimo) =>
  ok(
    nome,
    medido >= minimo,
    `mínimo=${minimo}  medido=${Number(medido).toFixed(4)}`
  );

const dir = 'public/vite/assets';
const arquivo = readdirSync(dir).find(f => /^widget-.*\.css$/.test(f));
if (!arquivo) {
  console.error('FALHA: não achei o CSS do widget em public/vite/assets.');
  console.error('Rode `bin/vite build --force` antes deste check.');
  process.exit(2);
}
const CSS = readFileSync(`${dir}/${arquivo}`, 'utf8');

// O `<style>` do servidor, vindo do serviço Ruby de verdade.
const tokensDoServidor = cor =>
  execFileSync(
    'ruby',
    [
      '-r./app/services/widget_tokens',
      '-e',
      `print WidgetTokens.new(ARGV[0]).css`,
      cor,
    ],
    { encoding: 'utf8' }
  );

const luminancia = ([r, g, b]) => {
  const f = c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const contraste = (a, b) => {
  const [l1, l2] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
};
const rgb = s => s.match(/\d+/g).slice(0, 3).map(Number);

// A árvore real da conversa, com as classes que os componentes aplicam. Quatro
// linhas, porque o aceite precisa das quatro situações: bolha do agente, bolha
// do visitante que abre bloco, bolha do visitante que CONTINUA (é ela que tem o
// canto de 6 px no topo) e bolha do agente que continua.
// `dir` NÃO é enfeite nesta página. O canto quebrado do balão é escrito com as
// variantes `ltr:`/`rtl:` do Tailwind, e o Tailwind as compila para
// `:where([dir=ltr], [dir=ltr] *)`. Num documento SEM `dir`, nenhuma das duas
// casa e a bolha sai com os quatro cantos livres — que foi exatamente o que
// este check mediu na primeira execução, com 20px onde o aceite pede 6px.
// No app de verdade quem escreve o atributo é o watcher `isRTL` de `App.vue`,
// com `immediate: true`, antes do primeiro paint. Aqui ele é escrito à mão, e é
// por isso que o espelho RTL também é medido lá embaixo.
const monta = (cor, tema, direcao = 'ltr') => `<!doctype html>
<html dir="${direcao}"><head>
  <style>${CSS}</style>
  <style>${tokensDoServidor(cor)}</style>
</head>
<body style="margin:0">
  <div id="app" class="woot-widget-app" style="width:400px">
    <div class="${tema === 'dark' ? 'dark' : ''}">
      <div class="conversation--container">
        <div class="conversation-wrap">
          <div class="messages-wrap">

            <div class="agent-message-wrap group">
              <div id="linha-agente" class="agent-message">
                <div class="avatar-wrap"><div class="user-thumbnail-box"></div></div>
                <div class="message-wrap">
                  <div class="flex w-full gap-1">
                    <div class="space-y-2">
                      <div class="chat-bubble-wrap">
                        <div id="agente" class="chat-bubble agent bg-white dark:bg-n-solid-3 text-n-slate-12">
                          <div class="message-content text-n-slate-12">
                            <p>Texto suficientemente longo para a linha alcancar o teto de largura e nao parar antes dele por falta de conteudo. <a id="link-agente" class="link" href="#">um link</a></p>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="agent-message-wrap group is-continuacao">
              <div class="agent-message">
                <div class="avatar-wrap"><div class="user-thumbnail-box"></div></div>
                <div class="message-wrap">
                  <div class="flex w-full gap-1">
                    <div class="space-y-2">
                      <div class="chat-bubble-wrap">
                        <div id="agente-continua" class="chat-bubble agent bg-white dark:bg-n-solid-3 text-n-slate-12">
                          <div class="message-content text-n-slate-12"><p>Continuacao.</p></div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="user-message-wrap group is-abertura">
              <div id="linha-visitante" class="flex gap-1 user-message">
                <div class="message-wrap">
                  <div class="flex justify-end gap-1">
                    <div id="visitante" class="chat-bubble user bg-w-brand text-w-on-brand">
                      Texto suficientemente longo para a linha alcancar o teto de largura e nao parar antes dele por falta de conteudo.
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="user-message-wrap group is-continuacao">
              <div class="flex gap-1 user-message">
                <div class="message-wrap">
                  <div class="flex justify-end gap-1">
                    <div id="visitante-continua" class="chat-bubble user bg-w-brand text-w-on-brand">Ok</div>
                  </div>
                </div>
              </div>
            </div>

          </div>
        </div>
      </div>
    </div>
  </div>
</body></html>`;

const navegador = await chromium.launch();
const pagina = await navegador.newPage();

const estilo = (seletor, props) =>
  pagina.locator(seletor).evaluate((el, chaves) => {
    const s = getComputedStyle(el);
    return Object.fromEntries(chaves.map(k => [k, s[k]]));
  }, props);

const largura = seletor =>
  pagina.locator(seletor).evaluate(el => el.getBoundingClientRect().width);

const medir = async (cor, tema) => {
  const rotulo = `[${cor} · ${tema}]`;
  await pagina.setContent(monta(cor, tema, 'ltr'));
  await pagina.locator('#visitante').waitFor();

  // ── 1. Sem sombra. `none` LITERAL, que é o que o aceite diz. ──────────────
  const sombraAgente = await estilo('#agente', ['boxShadow']);
  const sombraVisitante = await estilo('#visitante', ['boxShadow']);
  igual(
    `${rotulo} boxShadow da bolha do agente`,
    sombraAgente.boxShadow,
    'none'
  );
  igual(
    `${rotulo} boxShadow da bolha do visitante`,
    sombraVisitante.boxShadow,
    'none'
  );

  // ── 2. Contraste — as quatro medições que o aceite pede ───────────────────
  const visitante = await estilo('#visitante', ['color', 'backgroundColor']);
  aoMenos(
    `${rotulo} contraste do texto na bolha do VISITANTE`,
    contraste(rgb(visitante.color), rgb(visitante.backgroundColor)),
    ALVO_CONTRASTE
  );

  const agente = await estilo('#agente', ['color', 'backgroundColor']);
  aoMenos(
    `${rotulo} contraste do texto na bolha do AGENTE`,
    contraste(rgb(agente.color), rgb(agente.backgroundColor)),
    ALVO_CONTRASTE
  );

  // Aceite 2 da §C.5: o link na bolha do agente media 2,27:1 no tema claro.
  const link = await estilo('#link-agente', ['color']);
  aoMenos(
    `${rotulo} contraste do LINK na bolha do agente`,
    contraste(rgb(link.color), rgb(agente.backgroundColor)),
    ALVO_CONTRASTE
  );

  // ── 3. Geometria: raio 20/6, corpo 15/22, max-width 82% ───────────────────
  const geoAgente = await estilo('#agente', [
    'borderTopLeftRadius',
    'borderTopRightRadius',
    'borderBottomLeftRadius',
    'borderBottomRightRadius',
    'fontSize',
    'lineHeight',
  ]);
  igual(
    `${rotulo} agente · raio livre (topo esq.)`,
    geoAgente.borderTopLeftRadius,
    '20px'
  );
  igual(
    `${rotulo} agente · raio livre (topo dir.)`,
    geoAgente.borderTopRightRadius,
    '20px'
  );
  igual(
    `${rotulo} agente · canto de origem (base esq.)`,
    geoAgente.borderBottomLeftRadius,
    '6px'
  );
  igual(
    `${rotulo} agente · corpo`,
    `${geoAgente.fontSize}/${geoAgente.lineHeight}`,
    '15px/22px'
  );

  const geoVisitante = await estilo('#visitante', [
    'borderTopRightRadius',
    'borderBottomRightRadius',
    'fontSize',
    'lineHeight',
  ]);
  igual(
    `${rotulo} visitante · canto de origem (base dir.)`,
    geoVisitante.borderBottomRightRadius,
    '6px'
  );
  igual(
    `${rotulo} visitante · corpo`,
    `${geoVisitante.fontSize}/${geoVisitante.lineHeight}`,
    '15px/22px'
  );

  // O canto quebrado da CONTINUAÇÃO — o que os seletores de irmão faziam.
  const contAgente = await estilo('#agente-continua', ['borderTopLeftRadius']);
  igual(
    `${rotulo} agente em continuação · canto quebrado no topo`,
    contAgente.borderTopLeftRadius,
    '6px'
  );
  const contVisitante = await estilo('#visitante-continua', [
    'borderTopRightRadius',
  ]);
  igual(
    `${rotulo} visitante em continuação · canto quebrado no topo`,
    contVisitante.borderTopRightRadius,
    '6px'
  );

  // 82% MEDIDO, não declarado: a razão entre a largura pintada da linha e a da
  // lista. Era 88% × 90% = 79,2% efetivos do lado do agente — o número
  // declarado nunca tinha sido o medido.
  const lista = await largura('.messages-wrap');
  const razaoAgente = (await largura('#linha-agente')) / lista;
  const razaoVisitante = (await largura('#linha-visitante')) / lista;
  igual(
    `${rotulo} largura da linha do agente é 82% da lista`,
    razaoAgente.toFixed(3),
    (0.82).toFixed(3)
  );
  igual(
    `${rotulo} largura da linha do visitante é 82% da lista`,
    razaoVisitante.toFixed(3),
    (0.82).toFixed(3)
  );
};

// Sem laço com `await` dentro: as quatro combinações escritas uma a uma, que é
// o método — uma página, quatro estados, na ordem em que o relatório os cita.
await medir(CORES[0], TEMAS[0]);
await medir(CORES[0], TEMAS[1]);
await medir(CORES[1], TEMAS[0]);
await medir(CORES[1], TEMAS[1]);

// ── O espelho RTL ───────────────────────────────────────────────────────────
// `_conversation.scss` carrega ~30 pares `ltr:`/`rtl:`, e o risco R23 do plano
// diz que toda tarefa que toca este arquivo os preserva. O bloco 2.03 reescreve
// oito declarações de raio; medir o espelho é o que prova que os pares
// sobreviveram — em árabe ou hebraico o canto de origem troca de lado, e não há
// snapshot em `dir="rtl"` para pegar isso.
await pagina.setContent(monta(CORES[1], TEMAS[0], 'rtl'));
await pagina.locator('#visitante').waitFor();
const rtlAgente = await estilo('#agente', [
  'borderBottomRightRadius',
  'borderBottomLeftRadius',
]);
igual(
  '[rtl] agente · canto de origem espelhado para a base DIREITA',
  rtlAgente.borderBottomRightRadius,
  '6px'
);
igual(
  '[rtl] agente · a base esquerda volta a ser livre',
  rtlAgente.borderBottomLeftRadius,
  '20px'
);
const rtlVisitante = await estilo('#visitante', ['borderBottomLeftRadius']);
igual(
  '[rtl] visitante · canto de origem espelhado para a base ESQUERDA',
  rtlVisitante.borderBottomLeftRadius,
  '6px'
);
const rtlContinua = await estilo('#visitante-continua', [
  'borderTopLeftRadius',
]);
igual(
  '[rtl] visitante em continuação · canto quebrado espelhado',
  rtlContinua.borderTopLeftRadius,
  '6px'
);

// ─────────────────────────────────────────────────────────────────────────────
// A SEGUNDA SUPERFÍCIE: O PREVIEW DO PAINEL — bloco 2.03, segunda metade
//
// O mixin `widget-shape` foi escrito dizendo que QUATRO superfícies usam os
// mesmos números, e por muito tempo `@include widget-shape` apareceu uma vez
// só. A tela em que o cliente ESCOLHE a cor — Caixas de entrada › Aparência —
// desenhava as duas bolhas de exemplo com números próprios
// (`rounded-[1.25rem] rounded-br-[0.25rem] text-sm shadow max-w-[85%]`), e três
// deles contradiziam o widget que ela promete mostrar. Um preview que mente é
// pior que preview nenhum: o cliente aprova o que não vai ver.
//
// ── Por que esta página não sai do bundle do widget ──────────────────────────
//
// Porque o preview NÃO está no bundle do widget: ele é um componente do
// dashboard, e `public/vite/assets/widget-*.css` não contém uma linha dele. As
// três fontes do que o navegador pinta ali são montadas aqui, cada uma pelo
// compilador de verdade — nada de literal copiado:
//
//   1. os utilitários (`bg-w-brand`, `text-wp-text`, `px-4`…) saem do
//      Tailwind CLI rodando com o `tailwind.config.js` REAL, com o conteúdo
//      restrito ao SFC. É o que pega, por exemplo, `text-sm` valendo 14/20 —
//      um `grep` por "text-sm" não sabe quanto isso mede;
//   2. os tokens (`--w-bubble-*`, `--solid-2`, `--slate-12`) saem do `<style>`
//      de `Widget.vue` compilado com `sass`, que é onde mora o
//      `@include widget-shape`;
//   3. a marca chega por estilo INLINE, vinda de `brandTokens()` — a mesma
//      função que o componente chama em produção, não uma cópia da fórmula.
//
// E a ÁRVORE é lida do próprio `WidgetBody.vue`: o `<template>` é extraído do
// arquivo, com as interpolações trocadas por texto. Copiar a marcação para cá
// faria o check ficar verde sobre uma árvore que não existe mais no dia em que
// alguém mudasse uma classe — que é a falha nº 4 desta sessão.
//
// ⚠️ LIMITE CONHECIDO, para ninguém ler mais do que está medido: esta página
// tem a cascata PRÓPRIA do preview (preflight + utilitários + estilo dos dois
// SFCs). Ela NÃO carrega os catch-alls `!important` de `_wa-skin.scss`, que o
// `sass` sozinho não compila (`@apply`). É por isso que os tokens do preview
// são `wp-*`/`w-*` e não `n-*` — justamente para escapar deles —, mas uma
// regressão introduzida no skin não seria vista aqui.
const requireDaqui = createRequire(import.meta.url);
const dirSass = readdirSync('node_modules/.pnpm').find(d => /^sass@/.test(d));
if (!dirSass) {
  console.error('FALHA: sass não encontrado em node_modules/.pnpm.');
  process.exit(2);
}
const sass = requireDaqui(
  resolve('node_modules/.pnpm', dirSass, 'node_modules/sass')
);

const SFC_WIDGET =
  'app/javascript/dashboard/modules/widget-preview/components/Widget.vue';
const SFC_BODY =
  'app/javascript/dashboard/modules/widget-preview/components/WidgetBody.vue';

const cssDoSFC = caminho => {
  const sfc = readFileSync(caminho, 'utf8');
  const bloco = /<style[^>]*lang="scss"[^>]*>([\s\S]*?)<\/style>/.exec(sfc);
  if (!bloco) return '';
  // `logger: silent` porque a saída deste arquivo É o resultado: os avisos de
  // `mixed-decls` do sass (28, todos vindos de `_tokens_values.scss`) afogariam
  // as asserções. Eles não são deste bloco e não mudam o CSS gerado.
  return sass.compileString(bloco[1], {
    url: pathToFileURL(caminho),
    logger: sass.Logger.silent,
  }).css;
};

// Texto longo porque a razão de 82% só é medível quando a linha ENCOSTA no
// teto; com "Olá" a bolha para antes e o número mediria o conteúdo.
const TEXTO =
  'Texto suficientemente longo para a linha alcancar o teto de largura e nao parar antes dele por falta de conteudo.';
const marcacaoDoSFC = caminho => {
  const sfc = readFileSync(caminho, 'utf8');
  const inicio = sfc.indexOf('<template>') + '<template>'.length;
  const fim = sfc.lastIndexOf('</template>');
  return sfc.slice(inicio, fim).replace(/\{\{[\s\S]*?\}\}/g, TEXTO);
};

const tailwindDoPreview = () => {
  const temp = mkdtempSync(join(tmpdir(), 'bubble-preview-'));
  const entrada = join(temp, 'in.css');
  const saida = join(temp, 'out.css');
  writeFileSync(entrada, '@tailwind base;\n@tailwind utilities;\n');
  execFileSync(
    'node_modules/.bin/tailwindcss',
    [
      '-c',
      'tailwind.config.js',
      '-i',
      entrada,
      '-o',
      saida,
      '--content',
      SFC_BODY,
    ],
    { encoding: 'utf8', stdio: 'pipe' }
  );
  return readFileSync(saida, 'utf8');
};

const CSS_UTILITARIOS = tailwindDoPreview();
const CSS_TOKENS_PREVIEW = cssDoSFC(SFC_WIDGET);
const CSS_BODY = cssDoSFC(SFC_BODY);
const ARVORE_PREVIEW = marcacaoDoSFC(SFC_BODY);

// A mesma divisão de `Widget.vue`: `.wp-tokens` carrega os tokens e recebe a
// marca por inline; o TEMA mora no filho, porque inline vence classe no mesmo
// elemento e um `.wp-theme-dark` aqui nunca reapontaria nada.
const montaPreview = (cor, tema, direcao = 'ltr') => {
  const inline = Object.entries(brandTokens(cor))
    .map(([chave, valor]) => `${chave}:${valor}`)
    .join(';');
  return `<!doctype html>
<html dir="${direcao}"><head>
  <style>${CSS_UTILITARIOS}</style>
  <style>${CSS_TOKENS_PREVIEW}</style>
  <style>${CSS_BODY}</style>
</head>
<body style="margin:0">
  <div class="wp-tokens" style="width:400px;${inline}">
    <div class="${tema === 'dark' ? 'wp-theme-dark' : 'wp-theme-light'}">
      ${ARVORE_PREVIEW}
    </div>
  </div>
</body></html>`;
};

// Seletor ausente não pode virar exceção: quando a árvore ainda é a antiga, o
// check tem de REPROVAR com o mesmo número de asserções, e não morrer no meio —
// senão o vermelho e o verde não são comparáveis.
const estiloTolerante = async (seletor, props) => {
  if ((await pagina.locator(seletor).count()) === 0) {
    return Object.fromEntries(props.map(k => [k, '(seletor ausente)']));
  }
  return estilo(seletor, props);
};
const razaoNaLinha = async seletor => {
  if ((await pagina.locator(seletor).count()) === 0) return Number.NaN;
  return pagina
    .locator(seletor)
    .evaluate(
      el =>
        el.getBoundingClientRect().width /
        el.parentElement.getBoundingClientRect().width
    );
};
const contrasteDoEstilo = e =>
  /^rgb/.test(e.color) && /^rgb/.test(e.backgroundColor)
    ? contraste(rgb(e.color), rgb(e.backgroundColor))
    : Number.NaN;

const PROPS = [
  'boxShadow',
  'color',
  'backgroundColor',
  'borderTopLeftRadius',
  'borderTopRightRadius',
  'borderBottomLeftRadius',
  'borderBottomRightRadius',
  'fontSize',
  'lineHeight',
];

const medirPreview = async (cor, tema) => {
  const rotulo = `[preview · ${cor} · ${tema}]`;
  await pagina.setContent(montaPreview(cor, tema, 'ltr'));

  const visitante = await estiloTolerante('.wp-bubble--user', PROPS);
  const agente = await estiloTolerante('.wp-bubble--agent', PROPS);

  igual(
    `${rotulo} boxShadow do balão do visitante`,
    visitante.boxShadow,
    'none'
  );
  igual(`${rotulo} boxShadow do balão do agente`, agente.boxShadow, 'none');

  aoMenos(
    `${rotulo} contraste do texto no balão do VISITANTE`,
    contrasteDoEstilo(visitante),
    ALVO_CONTRASTE
  );
  aoMenos(
    `${rotulo} contraste do texto no balão do AGENTE`,
    contrasteDoEstilo(agente),
    ALVO_CONTRASTE
  );

  igual(
    `${rotulo} visitante · raio livre (topo esq.)`,
    visitante.borderTopLeftRadius,
    '20px'
  );
  igual(
    `${rotulo} visitante · canto de origem (base dir.)`,
    visitante.borderBottomRightRadius,
    '6px'
  );
  igual(
    `${rotulo} visitante · corpo`,
    `${visitante.fontSize}/${visitante.lineHeight}`,
    '15px/22px'
  );

  igual(
    `${rotulo} agente · raio livre (topo dir.)`,
    agente.borderTopRightRadius,
    '20px'
  );
  igual(
    `${rotulo} agente · canto de origem (base esq.)`,
    agente.borderBottomLeftRadius,
    '6px'
  );
  igual(
    `${rotulo} agente · corpo`,
    `${agente.fontSize}/${agente.lineHeight}`,
    '15px/22px'
  );

  // 82% MEDIDO na linha, contra o bloco que a contém — a mesma conta que o
  // widget faz acima. Era 85% declarado do lado do visitante, e do lado do
  // agente não havia teto NENHUM: a bolha ia até a borda da lista.
  igual(
    `${rotulo} largura da linha do visitante é 82% do bloco`,
    (await razaoNaLinha('.wp-bubble-row--user')).toFixed(3),
    (0.82).toFixed(3)
  );
  igual(
    `${rotulo} largura da linha do agente é 82% do bloco`,
    (await razaoNaLinha('.wp-bubble-row--agent')).toFixed(3),
    (0.82).toFixed(3)
  );
};

await medirPreview(CORES[0], TEMAS[0]);
await medirPreview(CORES[0], TEMAS[1]);
await medirPreview(CORES[1], TEMAS[0]);
await medirPreview(CORES[1], TEMAS[1]);

// ── O espelho RTL do preview ────────────────────────────────────────────────
// Risco R23. O preview escrevia o canto com `rounded-br-`/`rounded-bl-` e
// empurrava a linha do visitante com `ml-auto`: os três são FÍSICOS, e em
// árabe ou hebraico o bico do balão ficava do lado errado, com a linha do
// visitante presa à direita. Trocados por propriedades lógicas, viram sozinhos.
await pagina.setContent(montaPreview(CORES[1], TEMAS[0], 'rtl'));
const rtlVisitantePreview = await estiloTolerante('.wp-bubble--user', PROPS);
igual(
  '[preview · rtl] visitante · canto de origem espelhado para a base ESQUERDA',
  rtlVisitantePreview.borderBottomLeftRadius,
  '6px'
);
igual(
  '[preview · rtl] visitante · a base direita volta a ser livre',
  rtlVisitantePreview.borderBottomRightRadius,
  '20px'
);
const rtlAgentePreview = await estiloTolerante('.wp-bubble--agent', PROPS);
igual(
  '[preview · rtl] agente · canto de origem espelhado para a base DIREITA',
  rtlAgentePreview.borderBottomRightRadius,
  '6px'
);
// A linha do visitante encosta no lado do FIM, que em RTL é a esquerda: a
// margem automática tem de estar à DIREITA. Com `ml-auto` ela ficava à
// esquerda e a linha continuava colada na direita.
const rtlLinha = await estiloTolerante('.wp-bubble-row--user', [
  'marginLeft',
  'marginRight',
]);
igual(
  '[preview · rtl] linha do visitante · margem automática espelhada',
  `${rtlLinha.marginLeft}|${parseFloat(rtlLinha.marginRight) > 0}`,
  '0px|true'
);

await navegador.close();

const falhas = resultados.filter(r => !r.ok);
console.log(
  `\n${resultados.length - falhas.length}/${resultados.length} asserções ok`
);
process.exit(falhas.length ? 1 : 0);
