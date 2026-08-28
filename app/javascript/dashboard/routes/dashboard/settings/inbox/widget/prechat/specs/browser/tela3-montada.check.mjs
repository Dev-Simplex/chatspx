/* eslint-disable no-console -- Verificador de linha de comando: a saída no
   console É o resultado, lida por quem roda e colada no relatório do bloco. */
/**
 * Mecanismo de aceite do bloco 3.14 — a Tela 3 EM NAVEGADOR, nos dois temas.
 *
 * O jsdom prova lógica e não prova tela. Três coisas que o `PreChatPage.spec.js`
 * dá como verdes e que só um navegador desmente:
 *
 *   1. **o motivo do teto ser LEGÍVEL.** O aceite pede "o 9º campo impossível
 *      com o motivo à vista". O jsdom vê `data-testid="field-limit-reason"` no
 *      DOM e para por aí — não resolve cascata. A classe `text-n-amber-11` lê
 *      uma custom property reapontada em `_next-colors.scss`; se ela não
 *      existir no CSS compilado, o Tailwind descarta a classe em SILÊNCIO e o
 *      motivo sai na cor herdada, indistinguível do resto (regra: cor se prova
 *      COMPUTADA, nunca por leitura do fonte);
 *   2. **o `<select>` desaparecer de verdade.** `exists() === false` no jsdom
 *      não é o mesmo que "não há por onde clicar";
 *   3. **acessibilidade.** Rótulo associado, contraste e papel são medidos por
 *      `axe-core` no DOM renderizado, e o painel tem DOIS temas — o escuro é
 *      onde os catch-alls com `!important` do `_wa-skin.scss` agem.
 *
 *   node app/javascript/dashboard/routes/dashboard/settings/inbox/widget/prechat/specs/browser/tela3-montada.check.mjs
 */
import {
  readFileSync,
  writeFileSync,
  mkdtempSync,
  mkdirSync,
  existsSync,
} from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { build } from 'vite';
import vue from '@vitejs/plugin-vue';

// A raiz sai de subir ate o `package.json`, e nao de uma contagem de `../`:
// contar niveis quebra em silencio quando o arquivo muda de pasta. E `repoRoot`
// vem de `import.meta.url` de proposito — numa worktree, o `cwd` pode ser outro
// e o harness passaria a medir a arvore de origem.
const repoRoot = (() => {
  let dir = dirname(fileURLToPath(import.meta.url));
  while (!existsSync(join(dir, 'package.json'))) {
    const acima = dirname(dir);
    if (acima === dir) throw new Error('nao achei a raiz do repositorio');
    dir = acima;
  }
  return dir;
})();

const results = [];
const check = (name, actual, expected) => {
  const ok = String(actual) === String(expected);
  results.push({ name, ok });
  console.log(
    `${ok ? '  ok  ' : ' FAIL '} ${name}\n        esperado=${expected}  recebido=${actual}`
  );
};

// A pasta de trabalho fica DENTRO do repositorio (`tmp/`, ja no .gitignore).
// Em /tmp, o `import 'vue-i18n'` do entry gerado nao resolve: o rollup procura
// `node_modules` subindo a partir do IMPORTADOR, e /tmp nao tem nenhum.
mkdirSync(join(repoRoot, 'tmp'), { recursive: true });
const dir = mkdtempSync(join(repoRoot, 'tmp', 'tela3-'));

// ── 1. Os dublês, com a forma REAL de cada contrato ──────────────────────────
// O store do painel e o router não sobem aqui, então entram por alias. O que
// eles devolvem é a forma que o servidor devolve: a inbox recém-criada
// (`web_widget.rb#validate_pre_chat_options`, três campos padrão desligados) e
// os atributos de `api/v1/models/_custom_attribute_definition.json.jbuilder`.
const atributo = (chave, nome) => ({
  id: chave.length,
  attribute_display_name: nome,
  attribute_display_type: 'text',
  attribute_description: '',
  auto_provisioned_from_website: false,
  attribute_key: chave,
  regex_pattern: null,
  regex_cue: null,
  attribute_values: [],
  attribute_model: 'contact_attribute',
  default_value: null,
  created_at: '2026-08-01T12:00:00.000Z',
  updated_at: '2026-08-01T12:00:00.000Z',
});

const INBOX = {
  id: 7,
  name: 'Site da Simplex',
  channel_type: 'Channel::WebWidget',
  pre_chat_form_enabled: true,
  pre_chat_form_options: {
    pre_chat_message: 'Share your queries or comments here.',
    pre_chat_fields: [
      {
        field_type: 'standard',
        label: 'Email Id',
        name: 'emailAddress',
        type: 'email',
        required: true,
        enabled: false,
      },
      {
        field_type: 'standard',
        label: 'Full name',
        name: 'fullName',
        type: 'text',
        required: false,
        enabled: false,
      },
      {
        field_type: 'standard',
        label: 'Phone number',
        name: 'phoneNumber',
        type: 'text',
        required: false,
        enabled: false,
      },
    ],
  },
  additional_attributes: {},
};

const ATRIBUTOS = [
  atributo('cargo', 'Cargo'),
  atributo('empresa', 'Empresa'),
  atributo('faturamento', 'Faturamento'),
  atributo('cidade', 'Cidade'),
  atributo('origem', 'Origem'),
  atributo('orcamento', 'Orçamento'),
];

writeFileSync(
  join(dir, 'store-shim.js'),
  `import { computed, reactive } from 'vue';
const estado = reactive({ inbox: ${JSON.stringify(INBOX)} });
const atributos = ${JSON.stringify(ATRIBUTOS)};
export const useStore = () => ({
  getters: {
    'inboxes/getInbox': () => estado.inbox,
    'inboxes/getUIFlags': {},
    'attributes/getAttributes': atributos,
    'accounts/isRTL': false,
  },
  dispatch: async () => {},
});
export const useMapGetter = chave =>
  computed(() => (chave === 'attributes/getAttributes' ? atributos : false));
`
);

writeFileSync(
  join(dir, 'router-shim.js'),
  `export const useRouter = () => ({ push: async () => {} });
export const onBeforeRouteLeave = () => {};
export const useRoute = () => ({ params: {}, query: {} });
`
);

const localeJson = (locale, arquivo) =>
  JSON.parse(
    readFileSync(
      join(
        repoRoot,
        `app/javascript/dashboard/i18n/locale/${locale}/${arquivo}`
      ),
      'utf8'
    )
  );

const mensagens = Object.fromEntries(
  ['pt_BR', 'en'].map(locale => [
    locale,
    {
      ...localeJson(locale, 'inboxWidget.json'),
      ...localeJson(locale, 'inboxMgmt.json'),
    },
  ])
);

writeFileSync(
  join(dir, 'entry.js'),
  `import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import PreChatPage from '${join(repoRoot, 'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/prechat/PreChatPage.vue')}';
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  fallbackLocale: 'en',
  messages: ${JSON.stringify(mensagens)},
});
const app = createApp(PreChatPage, { inboxId: 7 });
app.use(i18n);
app.mount('#app');
`
);

// ── 2. O bundle, com os aliases REAIS do projeto ─────────────────────────────
const alias = [
  {
    find: /^dashboard\/composables\/store$/,
    replacement: join(dir, 'store-shim.js'),
  },
  { find: /^vue-router$/, replacement: join(dir, 'router-shim.js') },
  {
    find: 'components',
    replacement: join(repoRoot, 'app/javascript/dashboard/components'),
  },
  {
    find: 'next',
    replacement: join(repoRoot, 'app/javascript/dashboard/components-next'),
  },
  {
    find: 'dashboard',
    replacement: join(repoRoot, 'app/javascript/dashboard'),
  },
  {
    find: 'helpers',
    replacement: join(repoRoot, 'app/javascript/shared/helpers'),
  },
  { find: 'shared', replacement: join(repoRoot, 'app/javascript/shared') },
  { find: 'widget', replacement: join(repoRoot, 'app/javascript/widget') },
  {
    find: 'assets',
    replacement: join(repoRoot, 'app/javascript/dashboard/assets'),
  },
];

console.log('… empacotando a Tela 3 real (vite build)');
await build({
  // `root` e o REPOSITORIO, e nao a pasta temporaria: e de `root` que o vite
  // resolve `node_modules`. Com a temporaria, `import 'vue'` nao resolve.
  root: repoRoot,
  // sem `configFile: false` o vite carrega o `vite.config.ts` do projeto e
  // tenta construir os SETE entrypoints do produto.
  configFile: false,
  logLevel: 'error',
  plugins: [vue()],
  resolve: { alias },
  define: {
    __VUE_I18N_PROD_DEVTOOLS__: 'false',
    __INTLIFY_PROD_DEVTOOLS__: 'false',
    'process.env.NODE_ENV': '"production"',
  },
  build: {
    outDir: join(dir, 'dist'),
    emptyOutDir: true,
    lib: {
      entry: join(dir, 'entry.js'),
      formats: ['iife'],
      name: 'Tela3',
      fileName: () => 'tela3.js',
    },
    minify: false,
  },
});

// ── 3. O CSS de verdade ──────────────────────────────────────────────────────
console.log('… compilando o CSS real (tailwind + tokens + skin)');
const inCss = join(dir, 'in.css');
const outCss = join(dir, 'out.css');
writeFileSync(
  inCss,
  '@tailwind base;\n@tailwind components;\n@tailwind utilities;\n'
);
execFileSync(
  'pnpm',
  [
    'exec',
    'tailwindcss',
    '-c',
    'tailwind.config.js',
    '-i',
    inCss,
    '-o',
    outCss,
  ],
  { cwd: repoRoot, stdio: 'pipe' }
);
const TAILWIND = readFileSync(outCss, 'utf8');

// Mesmo caminho que `field-message-colors.check.mjs` usa: o `sass` entra por
// `createRequire` a partir da raiz medida, e nao por especificador nu.
const sass = createRequire(import.meta.url)(
  join(repoRoot, 'node_modules/.pnpm/sass@1.79.3/node_modules/sass')
);
const scss = arquivo =>
  sass.compile(
    join(repoRoot, `app/javascript/dashboard/assets/scss/${arquivo}`),
    {
      style: 'expanded',
    }
  ).css;
const NEXT_COLORS = scss('_next-colors.scss');
const SKIN = scss('_wa-skin.scss');

writeFileSync(
  join(dir, 'dist', 'index.html'),
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Tela 3 — pré-chat</title>
<style>${NEXT_COLORS}\n${TAILWIND}\n${SKIN}</style>
</head><body class="bg-n-background text-n-slate-12">
<main id="app" class="p-6"></main>
<script src="./tela3.js"></script>
</body></html>`
);

// ── 4. O navegador ───────────────────────────────────────────────────────────
const url = `file://${join(dir, 'dist', 'index.html')}`;
const browser = await chromium.launch();

// `browser.newContext()` e nao `browser.newPage()`: o @axe-core/playwright
// recusa uma page sem contexto proprio.
const abrir = async temaEscuro => {
  const context = await browser.newContext();
  const page = await context.newPage();
  const erros = [];
  page.on('pageerror', e => erros.push(e.message));
  await page.goto(url);
  if (temaEscuro) {
    await page.evaluate(() => document.documentElement.classList.add('dark'));
  }
  await page
    .locator('[data-testid="field-counter"]')
    .waitFor({ timeout: 15000 });
  return { page, erros };
};

const ligarCampo = async (page, nome) => {
  await page.selectOption('[data-testid="add-field-step-1"] select', nome);
  await page.waitForTimeout(60);
};

const OITO = [
  'emailAddress',
  'fullName',
  'phoneNumber',
  'cargo',
  'empresa',
  'faturamento',
  'cidade',
  'origem',
];

/**
 * A LINHA DE BASE do axe, e por que ela nao e um afrouxamento.
 *
 * A varredura roda inteira, em `serious`+`critical`. O que esta lista faz e
 * separar o que a Tela 3 DEVE e o que ela HERDA: cada entrada e um par de cores
 * exato, de um componente COMPARTILHADO que ja pinta o painel inteiro hoje, com
 * o bloco dono ao lado. Qualquer outra violacao — regra nova, ou o mesmo
 * `color-contrast` com OUTRO par de cores — reprova.
 *
 * Nao e "ignorar contraste": e recusar que o bloco 3.14 conserte um token de
 * cor da marca por dentro da tela de pre-chat, o que deixaria duas respostas no
 * produto para a mesma pergunta. As tres estao ESCALADAS no relatorio.
 */
const HERDADAS = new Map([
  // Botao vermelho "Remover" (`Button.vue` variante `faded ruby`), tambem em
  // AccountDelete, CollaboratorsPage, AddAttribute e mais. 3,88:1.
  ['color-contrast|#e54666|#ffffff', 'ruby-9 do Button faded — design system'],
  // Texto do `<select>` de `components-next/select/Select.vue` sobre a
  // superficie do painel. 4,14:1.
  ['color-contrast|#667781|#f0f2f5', 'slate do Select.vue — design system'],
  // Branco sobre a cor da marca: 2,27:1 — o MESMO numero que o aceite do bloco
  // 3.08 cita nominalmente. Cor da marca e assunto de 1.03/1.04/3.08.
  [
    'color-contrast|#ffffff|#2dc46f',
    'branco sobre a marca — blocos 1.03/1.04/3.08',
  ],
]);

const assinatura = no => {
  const cores =
    /foreground color: (#[0-9a-f]{6}), background color: (#[0-9a-f]{6})/i.exec(
      no.failureSummary ?? ''
    );
  return cores
    ? `${cores[1].toLowerCase()}|${cores[2].toLowerCase()}`
    : 'sem-cor';
};

const violacoesSerias = async page => {
  const r = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();
  const serias = r.violations.filter(v =>
    ['serious', 'critical'].includes(v.impact)
  );
  const proprias = [];
  const herdadas = [];
  serias.forEach(v =>
    v.nodes.forEach(no => {
      const chave = `${v.id}|${assinatura(no)}`;
      (HERDADAS.has(chave) ? herdadas : proprias).push({ chave, v, no });
    })
  );
  return { proprias, herdadas };
};

const medirTema = async escuro => {
  const tema = escuro ? 'ESCURO' : 'CLARO';
  console.log(
    `\n── tema ${tema} ─────────────────────────────────────────────`
  );
  const { page, erros } = await abrir(escuro);

  check(
    `[${tema}] a Tela 3 monta sem erro de runtime`,
    erros.join(' | ') || 'nenhum',
    'nenhum'
  );

  // O catálogo veio da conta: os 6 atributos entraram no `<select>`.
  const opcoes = await page.$$eval(
    '[data-testid="add-field-step-1"] option',
    os => os.map(o => o.textContent.trim())
  );
  check(
    `[${tema}] o catálogo oferece os 6 atributos da conta`,
    ['Cargo', 'Empresa', 'Faturamento', 'Cidade', 'Origem', 'Orçamento'].every(
      n => opcoes.includes(n)
    ),
    'true'
  );

  // ACEITE, cláusula 1 — o 9º campo é impossível COM O MOTIVO À VISTA.
  // Em SERIE: cada `enableField` le a lista ja com o anterior ligado, e e essa
  // acumulacao que faz o oitavo bater no teto.
  await OITO.reduce(
    (anterior, nome) => anterior.then(() => ligarCampo(page, nome)),
    Promise.resolve()
  );

  check(
    `[${tema}] o contador chegou ao teto`,
    (await page.locator('[data-testid="field-counter"]').innerText()).trim(),
    '8 de 8 campos'
  );

  const motivo = page.locator('[data-testid="field-limit-reason"]');
  check(
    `[${tema}] o motivo está VISÍVEL na tela`,
    await motivo.isVisible(),
    'true'
  );
  check(
    `[${tema}] e não é um retângulo de zero pixel`,
    ((await motivo.boundingBox())?.height ?? 0) > 8,
    'true'
  );

  // A cor COMPUTADA prova que `text-n-amber-11` resolveu. Herdar a cor do corpo
  // seria a classe descartada em silêncio — o motivo existiria e não se leria
  // como aviso.
  const corMotivo = await motivo.evaluate(el => getComputedStyle(el).color);
  const corCorpo = await page.$eval('#app', el => getComputedStyle(el).color);
  check(
    `[${tema}] o motivo NÃO herda a cor do corpo (${corMotivo} vs ${corCorpo})`,
    corMotivo !== corCorpo,
    'true'
  );

  check(
    `[${tema}] o 9º campo não tem por onde entrar: o seletor sumiu`,
    await page.locator('[data-testid="add-field-step-1"]').count(),
    0
  );
  check(
    `[${tema}] e o que sobrou está desabilitado`,
    await page.locator('[data-testid="add-field-disabled-1"]').isDisabled(),
    'true'
  );

  // ACEITE, cláusula 2 — validação NO BLUR, não a cada tecla.
  const rotulo = page.locator('[data-testid="field-label"] input').first();
  await rotulo.fill('');
  check(
    `[${tema}] rótulo vazio ainda SEM foco perdido: nenhuma mensagem`,
    await page
      .locator('text=Sem ele, o campo aparece com o nome interno')
      .count(),
    0
  );
  await rotulo.blur();
  await page.waitForTimeout(60);
  check(
    `[${tema}] depois do blur, a mensagem aparece`,
    await page
      .locator('text=Sem ele, o campo aparece com o nome interno')
      .count(),
    1
  );

  // Acessibilidade no DOM renderizado, com 8 campos abertos.
  const { proprias, herdadas } = await violacoesSerias(page);
  proprias.forEach(({ v, no }) =>
    console.log(
      `        · ${v.id}: ${no.target} :: ${(no.failureSummary || '').replace(/\n/g, ' ')}`
    )
  );
  check(
    `[${tema}] axe: nenhuma violação serious/critical FORA da linha de base`,
    proprias.map(({ chave }) => chave).join(', ') || 'nenhuma',
    'nenhuma'
  );
  const contagem = herdadas.reduce((acc, { chave }) => {
    acc[chave] = (acc[chave] ?? 0) + 1;
    return acc;
  }, {});
  console.log(
    `        (herdadas, escaladas: ${
      Object.entries(contagem)
        .map(([chave, n]) => `${HERDADAS.get(chave)} ×${n}`)
        .join('; ') || 'nenhuma'
    })`
  );

  await page.close();
};

await medirTema(false);
await medirTema(true);

await browser.close();

const falhas = results.filter(r => !r.ok);
console.log(
  `\n${results.length - falhas.length}/${results.length} asserções passaram`
);
process.exit(falhas.length ? 1 : 0);
