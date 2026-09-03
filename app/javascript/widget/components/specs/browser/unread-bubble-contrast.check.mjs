/* eslint-disable no-console -- Este arquivo é um verificador de linha de
   comando: a saída no console É o resultado dele, lida por quem roda e
   colada no relatório do bloco. Não é log esquecido em código de produção,
   que é o que a regra existe para pegar. */
/**
 * Trava a INTENÇÃO da bolha de mensagens não lidas — achado roteado em 18/08.
 *
 * A varredura da Onda 2 marcou `UnreadMessage.vue` como suspeito por ter
 * `bg-white` sem variante `dark:`, e a pergunta era se isso é defeito baselinado
 * ou escolha. É escolha, e este arquivo é o que impede que alguém a desfaça
 * "consertando" — porque um `dark:bg-n-solid-3` bem-intencionado passaria no
 * lint, passaria na revisão e só apareceria na tela de um cliente.
 *
 * POR QUE O PAR É BRANCO/PRETO FIXO
 *
 * As bolhas de não lidas não vivem no painel. O holder delas é despido no
 * `SDK_CSS` (`.has-unread-view` zera sombra, borda e raio), então elas flutuam
 * sobre o SITE DO CLIENTE — cujo tema o widget não conhece nem controla. Branco
 * com `text-n-black` (#000000, fixo) dá 21:1, o contraste máximo possível, e é
 * legível sobre qualquer página. A evidência de que foi decisão está na mesma
 * declaração do `_conversation.scss`: ela dá `dark:border-n-slate-11/50` à
 * BORDA — para separar a bolha branca de um site escuro — e no mesmo gesto
 * mantém o par. Quem pensou no escuro ali resolveu pela borda, de propósito.
 *
 * O QUE ESTE TESTE TRAVA, E O QUE ELE NÃO TRAVA
 *
 * Ele não exige que a bolha seja branca por ser branca. Ele exige que, nos DOIS
 * temas, o par fundo/texto da bolha continue com contraste máximo — que é a
 * intenção. Se alguém tornar o fundo temático e o texto continuar preto fixo, o
 * contraste desaba no escuro e o teste vermelhece apontando o número.
 *
 *   node app/javascript/widget/components/specs/browser/unread-bubble-contrast.check.mjs
 */
import { readFileSync, readdirSync } from 'node:fs';
import { chromium } from 'playwright';

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// O CSS do widget, como o build o produz — não um recorte escrito aqui.
const dir = 'public/vite/assets';
const arq = readdirSync(dir).find(f => /^widget-.*\.css$/.test(f));
if (!arq) {
  console.error('FALHA: não achei o CSS do widget em public/vite/assets.');
  console.error('Rode `bin/vite build --force` antes deste check.');
  process.exit(2);
}
const CSS = readFileSync(`${dir}/${arq}`, 'utf8');

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

const browser = await chromium.launch();
const page = await browser.newPage();

// Reproduz a árvore real: `.unread-messages > .chat-bubble-wrap > .chat-bubble`,
// com as classes que o componente aplica.
const monta = tema => `<!doctype html>
<html><head><style>${CSS}</style></head>
<body style="margin:0">
  <div id="app">
    <div class="${tema === 'dark' ? 'dark' : ''}">
      <div class="unread-messages">
        <div class="chat-bubble-wrap">
          <button id="bolha" class="chat-bubble agent bg-white">
            <div class="message-content">Resposta pendente número três.</div>
          </button>
        </div>
      </div>
    </div>
  </div>
</body></html>`;

// Os dois temas medidos em sequência, sem laço: o `no-await-in-loop` existe para
// pegar serialização acidental, e aqui ela é o método — uma página, dois estados.
const medirTema = async tema => {
  await page.setContent(monta(tema));
  await page.locator('#bolha').waitFor();
  const { bg, fg } = await page.locator('#bolha').evaluate(el => {
    const s = getComputedStyle(el);
    return { bg: s.backgroundColor, fg: s.color };
  });
  const razao = contraste(rgb(bg), rgb(fg));

  check(`[${tema}] fundo da bolha`, bg, 'rgb(255, 255, 255)');
  check(`[${tema}] texto da bolha`, fg, 'rgb(0, 0, 0)');
  // 21:1 é o teto do WCAG — preto puro sobre branco puro. A tolerância de duas
  // casas é a mesma regra do 1.02: comparar razão de contraste por igualdade
  // exata já custou meio dia nesta casa.
  check(
    `[${tema}] contraste é o máximo (21:1)`,
    razao.toFixed(2),
    (21).toFixed(2)
  );
};

await medirTema('light');
await medirTema('dark');

// E a borda, que é onde o modo escuro FOI tratado — a prova de que o par
// branco/preto é escolha e não esquecimento.
await page.setContent(monta('light'));
const bordaLight = await page
  .locator('#bolha')
  .evaluate(el => getComputedStyle(el).borderTopColor);
await page.setContent(monta('dark'));
const bordaDark = await page
  .locator('#bolha')
  .evaluate(el => getComputedStyle(el).borderTopColor);
check(
  'a borda MUDA entre os temas (é ela que trata o escuro)',
  String(bordaLight !== bordaDark),
  'true'
);

await browser.close();

const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
