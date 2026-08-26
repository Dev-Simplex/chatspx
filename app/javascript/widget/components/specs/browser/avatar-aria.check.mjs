/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado dele. */
/**
 * Prova do conserto de `role-img-alt` no `WAvatar` — triagem de 18/08.
 *
 * O QUE ELE PROVA, E POR QUE PRECISA DE NAVEGADOR
 *
 * `role="img"` **remove os filhos da árvore de acessibilidade**. As iniciais
 * ("ML") que aparecem na tela NÃO são lidas: para o leitor de tela o nó é uma
 * imagem sem nome. Isso não se vê no DOM nem em jsdom — é o cálculo de nome
 * acessível do navegador, e é o axe rodando de verdade que o revela.
 *
 * O defeito veio do `Avatar` do dashboard, que o bloco 1.08 replicou fielmente:
 * a réplica trouxe o defeito junto.
 *
 * ⚠️ NÃO USA O HARNESS DE PORTA FIXA. `chromium.launch()` direto, sem
 * `playwright.config.js`, sem `webServer`, sem 3038/3999/8899 — o harness é
 * recurso de slot único e está sob tranca do coordenador.
 *
 *   node app/javascript/widget/components/specs/browser/avatar-aria.check.mjs
 */
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

const results = [];
const check = (name, actual, expected) => {
  const ok = actual === expected;
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// A marcação vem do componente real, não é escrita aqui: extrai o `role="img"`
// e o `aria-label` de `WAvatar.vue`.
const componente = readFileSync(
  new URL('../../../ui/WAvatar.vue', import.meta.url),
  'utf8'
);
check(
  'WAvatar declara aria-label no nó com role="img"',
  String(/role="img"\s*\n\s*:aria-label="name/.test(componente)),
  'true'
);

const monta = comLabel => `<!doctype html>
<html lang="pt-BR"><head><title>t</title></head>
<body>
  <span style="display:inline-flex;width:20px;height:20px">
    <span role="img"${comLabel ? ' aria-label="Marina Lima"' : ''}
          style="display:inline-flex;align-items:center;justify-content:center;
                 width:20px;height:20px;background:#E1E9FF;color:#3A5BC7">ML</span>
  </span>
</body></html>`;

const browser = await chromium.launch();
// `newContext()` explícito: o `@axe-core/playwright` recusa uma página criada
// por `browser.newPage()` direto ("Please use browser.newContext()").
const contexto = await browser.newContext();
const page = await contexto.newPage();

const violacoesDe = async comLabel => {
  await page.setContent(monta(comLabel));
  await page.locator('[role="img"]').waitFor();
  const r = await new AxeBuilder({ page })
    .withRules(['role-img-alt'])
    .analyze();
  return r.violations.map(v => v.id);
};

// 1) o estado ANTES do conserto — a violação existe, e é ela mesma
check(
  'SEM aria-label o axe acusa role-img-alt',
  JSON.stringify(await violacoesDe(false)),
  '["role-img-alt"]'
);

// 2) o estado DEPOIS
check(
  'COM aria-label a violação desaparece',
  JSON.stringify(await violacoesDe(true)),
  '[]'
);

// 3) e o nome que o navegador calcula é o do agente, não um genérico
await page.setContent(monta(true));
check(
  'o nome acessível calculado é o do agente',
  await page
    .locator('[role="img"]')
    .evaluate(el => el.getAttribute('aria-label')),
  'Marina Lima'
);

await browser.close();
const failed = results.filter(r => !r.ok);
console.log(
  `\n${results.length - failed.length}/${results.length} asserções ok`
);
process.exit(failed.length ? 1 : 0);
