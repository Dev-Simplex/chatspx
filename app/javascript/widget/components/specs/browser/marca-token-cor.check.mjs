/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado dele, lida por quem roda e colada no relatório do
   bloco. Não é log esquecido em código de produção. */
/**
 * BLOCOS 1.03/1.04 · W1.6 — a COR COMPUTADA das quatro superfícies da marca.
 *
 * O aceite exige que borda e rótulo do chip, o "ver mensagens" das não lidas, o
 * "iniciar conversa" e o "ver todos os artigos" parem de ser pintados com a
 * MARCA CRUA e passem a sair de `--w-brand-readable` — a mesma marca já
 * escurecida até 4,5:1 pelo servidor (bloco 1.02), com par próprio no escuro.
 *
 * POR QUE ISTO NÃO É UM `.spec.js`
 *
 * jsdom não resolve `@apply`, não calcula cascade e não herda cor de folha
 * injetada. O companheiro deste arquivo — `specs/marcaSemEstiloInline.spec.js` —
 * monta os componentes de verdade e prova que o `:style` inline SUMIU; ele não
 * consegue dizer que cor sobrou na tela. Quem diz é o Chromium, aqui.
 *
 * O MÉTODO, E A ARMADILHA QUE ELE EVITA
 *
 * A marca entra DIVERGENTE do token: `--w-brand: #ff0000`. Se qualquer uma das
 * quatro superfícies voltar a ler a marca crua, ela aparece vermelha e o
 * verificador aponta o valor. Medir com marca e token na mesma cor daria verde
 * nos dois mundos — foi assim que o defeito atravessou a auditoria anterior.
 *
 * Nem classe nem CSS são escritos aqui: as classes saem do `<template>` dos
 * componentes reais, o `@apply` das regras escopadas sai do `<style>` deles, e
 * as utilitárias são compiladas pelo Tailwind com `tailwind.widget.config.js` —
 * o mesmo config que gera o CSS do widget.
 *
 *   node app/javascript/widget/components/specs/browser/marca-token-cor.check.mjs
 */
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';

const repoRoot = new URL('../../../../../../', import.meta.url).pathname;

const results = [];
const check = (name, ok, detalhe) => {
  results.push({ name, ok });
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}\n        ${detalhe}`);
};

const ler = rel => readFileSync(join(repoRoot, rel), 'utf8');

// A marca entra DIVERGENTE do legível. `--w-brand` é vermelho puro e não
// aparece em token nenhum dos mixins: é o corante da medição. Declarado aqui
// no topo porque a extração das tags (logo abaixo) já o usa.
const MARCA_CRUA = '#ff0000';
const CRU_RGB = 'rgb(255, 0, 0)';

// ── 1. Classes e `:style` vêm dos componentes REAIS ────────────────────────
const COMPONENTES = {
  chatOption: ler('app/javascript/shared/components/ChatOption.vue'),
  unread: ler('app/javascript/widget/components/UnreadMessageList.vue'),
  team: ler('app/javascript/widget/components/TeamAvailability.vue'),
  artigos: ler(
    'app/javascript/widget/components/pageComponents/Home/Article/ArticleBlock.vue'
  ),
};

const semComentario = fonte => fonte.replace(/<!--[\s\S]*?-->/g, '');

/**
 * Recorta o pedaço do template a partir de uma âncora. Existe porque
 * "o primeiro `<span>` do arquivo" não é o alvo: em `UnreadMessageList` o
 * primeiro `<span>` é o do botão de FECHAR, e medir ele daria verde sobre o
 * rótulo errado — o tipo de acerto por coincidência que não prova nada.
 */
const recorte = (fonte, ancora, rotulo) => {
  const i = semComentario(fonte).indexOf(ancora);
  if (i < 0) {
    console.error(`FALHA: não achei a âncora "${ancora}" em ${rotulo}`);
    process.exit(1);
  }
  return semComentario(fonte).slice(i);
};

/** A tag de abertura do primeiro elemento `tag` do trecho. */
const tagDe = (trecho, tag, rotulo) => {
  const aberta = trecho.match(new RegExp(`<${tag}\\b[^>]*>`));
  if (!aberta) {
    console.error(`FALHA: não achei <${tag}> em ${rotulo}`);
    process.exit(1);
  }
  return aberta[0];
};

/** O `class="…"` estático da tag. */
const classesDa = tagAberta =>
  (tagAberta.match(/\sclass="([^"]*)"/)?.[1] || '').replace(/\s+/g, ' ').trim();

/**
 * O `:style` de COR que a tag ainda tenha, TRADUZIDO para o `style=""` que o
 * Vue produziria com a marca crua no getter.
 *
 * Sem isto o verificador não seria vermelho antes da correção: ele monta a
 * página a partir das CLASSES, e um `:style` sobrevivente não apareceria — mas
 * é justamente ele que, na tela do visitante, vence a classe e pinta a marca
 * crua. Reproduzi-lo aqui é o que faz esta medição valer.
 */
const inlineDa = tagAberta => {
  const bind = tagAberta.match(/:style="\{([\s\S]*?)\}"/)?.[1];
  if (!bind || !/widgetColor/.test(bind)) return '';
  return bind
    .split(',')
    .map(par => par.trim())
    .filter(par => /widgetColor/.test(par))
    .map(par =>
      par
        .split(':')[0]
        .trim()
        .replace(/([A-Z])/g, '-$1')
    )
    .map(prop => `${prop.toLowerCase()}: ${MARCA_CRUA}`)
    .join('; ');
};

/** `class` + `style` prontos para ir ao HTML, a partir de uma âncora. */
const alvo = (fonte, ancora, tag, rotulo) => {
  const aberta = tagDe(recorte(fonte, ancora, rotulo), tag, rotulo);
  const inline = inlineDa(aberta);
  return {
    classes: classesDa(aberta),
    style: inline ? ` style="${inline}"` : '',
  };
};

/** O `@apply` de um seletor do bloco `<style>` do SFC. */
const applyDe = (fonte, seletor, rotulo) => {
  const bloco = fonte.match(
    new RegExp(`\\${seletor} \\{([\\s\\S]*?)\\n {2}\\}`)
  );
  const lista = bloco?.[1].match(/@apply ([^;]+);/)?.[1];
  if (!lista) {
    console.error(`FALHA: não achei @apply de ${seletor} em ${rotulo}`);
    process.exit(1);
  }
  return lista.replace(/\s+/g, ' ').trim();
};

// As regras escopadas entram como CLASSES: `@apply` já é lista de utilitária, e
// é assim que `handoff-mark-color.check.mjs` faz. O que muda aqui é que o
// `:style` da tag vem junto — ver `inlineDa`.
const APLICADAS = {
  chip: applyDe(COMPONENTES.chatOption, '.option', 'ChatOption.vue'),
  chipBotao: applyDe(
    COMPONENTES.chatOption,
    '.option-button',
    'ChatOption.vue'
  ),
  unreadBotao: applyDe(
    COMPONENTES.unread,
    '.clear-button',
    'UnreadMessageList.vue'
  ),
};

const ALVOS = {
  // Chip de resposta rápida: a borda está na `<li class="option">`; o rótulo, no
  // `<span>` dentro do `.option-button`.
  chip: alvo(COMPONENTES.chatOption, '<li', 'li', 'ChatOption.vue'),
  chipRotulo: alvo(
    COMPONENTES.chatOption,
    'option-button',
    'span',
    'ChatOption.vue'
  ),
  // Âncora obrigatória: o PRIMEIRO `<span>` do arquivo é o do botão de fechar.
  unreadRotulo: alvo(
    COMPONENTES.unread,
    'open-read-view-wrap',
    'span',
    'UnreadMessageList.vue'
  ),
  team: alvo(COMPONENTES.team, '<button', 'button', 'TeamAvailability.vue'),
  artigos: alvo(COMPONENTES.artigos, '<button', 'button', 'ArticleBlock.vue'),
};

// ── 2. As REGRAS, com a briga de cascade que existe na tela ────────────────
//
// O chip e o "ver mensagens" carregam DUAS classes: a do componente e a
// `.button` GLOBAL de `woot.scss`, cujo `@apply` traz `text-w-on-brand` — preto
// quando a marca é clara. Montar a página só com as classes do componente
// esconderia essa briga, e o verificador diria "usa o token" sobre um rótulo
// que na tela sai PRETO. Aqui as duas regras entram, e o navegador decide.
//
// A especificidade do fixture é MENOR que a de produção (`.unread-wrap
// .clear-button` = 0,2,0 aqui; com o atributo do `scoped` seria 0,3,0), o que
// torna a medição mais severa, nunca mais frouxa: se o token vence aqui, vence lá.
const APPLY_BUTTON = applyDe(
  ler('app/javascript/widget/assets/scss/woot.scss'),
  '.button',
  'woot.scss'
);

const dir = mkdtempSync(join(tmpdir(), 'marca-token-'));
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(
  inCss,
  [
    '@tailwind utilities;',
    `.button { @apply ${APPLY_BUTTON}; }`,
    `.option { @apply ${APLICADAS.chip}; }`,
    `.option .option-button { @apply ${APLICADAS.chipBotao}; }`,
    `.unread-wrap .clear-button { @apply ${APLICADAS.unreadBotao}; }`,
    '',
  ].join('\n')
);
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.widget.config.js',
    '-i',
    inCss,
    '-o',
    outCss,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const CSS = readFileSync(outCss, 'utf8');

// ── 3. Os VALORES dos tokens, lidos dos mixins do projeto ──────────────────
const tokensFonte = ler(
  'app/javascript/widget/assets/scss/_tokens_values.scss'
);
const mixin = nome => {
  const bloco = tokensFonte.match(
    new RegExp(`@mixin ${nome} \\{([\\s\\S]*?)\\n\\}`)
  )?.[1];
  if (!bloco) {
    console.error(`FALHA: não localizei o mixin ${nome}`);
    process.exit(1);
  }
  // ⚠️ O `//` do SCSS TEM de sair antes de virar CSS, e isto custou uma medição
  // inteira: o navegador não conhece comentário de linha, trata `//` como erro
  // de parse e descarta tudo até o PRÓXIMO `;` — que é o fim da declaração
  // seguinte. As três linhas de comentário acima de `--w-brand-readable`
  // engoliam justamente o token que este verificador existe para medir, e o
  // Tailwind caía no fallback `#2dc46f`. No tema escuro esse fallback é IGUAL
  // ao valor certo, então a medição passava sem medir nada.
  return bloco.replace(/^\s*\/\/.*$/gm, '').replace(/\/\/[^\n;{}]*$/gm, '');
};

// A cascata é montada como `_tokens.scss` a monta: `:root` recebe a paleta e a
// marca claras, `.dark` recebe as escuras por cima. `--w-brand-readable-dark`
// só existe no mixin claro, e o escuro aponta para ele — copiar só o mixin
// escuro daria um `var()` sem destino.
const CASCATA = `
:root { ${mixin('widget-palette-light')} ${mixin('widget-brand-light')} --w-brand: ${MARCA_CRUA}; }
.dark { ${mixin('widget-palette-dark')} ${mixin('widget-brand-dark')} --w-brand: ${MARCA_CRUA}; }
`;

const TEMAS = {
  claro: {
    fundo: '#ffffff',
    // `--w-brand-readable` do mixin claro: #1d824a.
    esperado: 'rgb(29, 130, 74)',
    esperadoHex: '#1d824a',
    classe: '',
  },
  escuro: {
    fundo: '#111111',
    // `--w-brand-readable` no escuro aponta para `--w-brand-readable-dark`: #2dc46f.
    esperado: 'rgb(45, 196, 111)',
    esperadoHex: '#2dc46f',
    classe: 'dark',
  },
};

// ── 4. A medição ───────────────────────────────────────────────────────────
const browser = await chromium.launch();
const page = await browser.newPage();

const pagina = ({ fundo, classe }) => `<!doctype html>
<html class="${classe}"><head>
<style>${CSS}</style>
<style>${CASCATA}</style>
</head>
<body style="margin:0;background:${fundo}">
  <ul>
    <li id="chip" class="${ALVOS.chip.classes}"${ALVOS.chip.style}>
      <button id="chip-botao" class="option-button button">
        <span id="chip-rotulo" class="${ALVOS.chipRotulo.classes}"${ALVOS.chipRotulo.style}>Falar com um humano</span>
      </button>
    </li>
  </ul>
  <div class="unread-wrap">
    <button id="unread" class="button clear-button">
      <span id="unread-rotulo" class="${ALVOS.unreadRotulo.classes}"${ALVOS.unreadRotulo.style}>Ver mensagens</span>
    </button>
  </div>
  <button id="team" class="${ALVOS.team.classes}"${ALVOS.team.style}>Iniciar conversa</button>
  <button id="artigos" class="${ALVOS.artigos.classes}"${ALVOS.artigos.style}>Ver todos os artigos</button>
</body></html>`;

const medirTema = async (nome, tema) => {
  await page.setContent(pagina(tema));
  await page.locator('#chip').waitFor();

  const { tokenDeclarado, ...lido } = await page.evaluate(() => {
    const s = id => getComputedStyle(document.getElementById(id));
    return {
      tokenDeclarado: getComputedStyle(document.documentElement)
        .getPropertyValue('--w-brand-readable')
        .trim(),
      chipBorda: s('chip').borderTopColor,
      chipRotulo: s('chip-rotulo').color,
      unread: s('unread-rotulo').color,
      team: s('team').color,
      artigos: s('artigos').color,
    };
  });

  // ── DUAS GUARDAS CONTRA FIXTURE QUEBRADO ─────────────────────────────────
  // 1) Token ausente: `var(--w-brand-readable, #2dc46f)` cai no FALLBACK, que no
  //    tema escuro é igual ao valor certo — o verificador passaria sem medir. Só
  //    ler a custom property no documento distingue os dois casos.
  check(
    `[${nome}] --w-brand-readable está DECLARADO no documento`,
    tokenDeclarado.toLowerCase() === tema.esperadoHex,
    `esperado=${tema.esperadoHex}  recebido=${tokenDeclarado || '(vazio — o Tailwind caiu no fallback)'}`
  );
  // 2) Token inválido: a propriedade cai para o herdado e TUDO vira preto; um
  //    verificador que só perguntasse "não é vermelho?" daria verde sobre isso.
  check(
    `[${nome}] os tokens RESOLVERAM — a medição está medindo`,
    Object.values(lido).every(cor => cor !== 'rgb(0, 0, 0)'),
    JSON.stringify(lido)
  );

  Object.entries(lido).forEach(([superficie, cor]) => {
    check(
      `[${nome}] ${superficie} usa --w-brand-readable, não a marca crua`,
      cor === tema.esperado,
      `esperado=${tema.esperado}  recebido=${cor}${cor === CRU_RGB ? '  ← MARCA CRUA' : ''}`
    );
  });
};

await medirTema('claro', TEMAS.claro);
await medirTema('escuro', TEMAS.escuro);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
if (falhas.length) {
  console.error(`FALHOU: ${falhas.map(f => f.name).join(' · ')}`);
  process.exit(1);
}
console.log('TODAS as asserções medidas no Chromium passaram.');
