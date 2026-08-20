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
import { readFileSync, readdirSync } from 'node:fs';
import { chromium } from 'playwright';

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

await navegador.close();

const falhas = resultados.filter(r => !r.ok);
console.log(
  `\n${resultados.length - falhas.length}/${resultados.length} asserções ok`
);
process.exit(falhas.length ? 1 : 0);
