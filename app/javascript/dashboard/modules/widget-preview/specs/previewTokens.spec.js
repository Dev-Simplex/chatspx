import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { pathToFileURL } from 'url';

/* `sass` nao e dependencia DECLARADA do projeto — ele chega pelo vite, e o pnpm
   so cria link em `node_modules/` para o que esta no `package.json`. Como este
   spec precisa compilar SCSS de verdade (e nao ler o arquivo como texto),
   resolve-se o pacote dentro do store do pnpm. Se um dia ele sair de la, o
   teste falha dizendo isso, em vez de passar sem compilar nada. */
const requireFromHere = createRequire(import.meta.url);
const sassDir = fs
  .readdirSync(path.resolve(process.cwd(), 'node_modules/.pnpm'))
  .find(dir => /^sass@/.test(dir));
if (!sassDir) throw new Error('sass nao encontrado em node_modules/.pnpm');
const sass = requireFromHere(
  path.resolve(
    process.cwd(),
    'node_modules/.pnpm',
    sassDir,
    'node_modules/sass'
  )
);

/**
 * D4 — o preview carregava ~74 custom properties de cor copiadas do widget.
 * Duas copias da mesma paleta divergem sem ninguem perceber. Este spec faz
 * duas perguntas, e as duas sao verificaveis:
 *
 *   1. sobrou alguma copia? (grep, o aceite literal do bloco 3.10)
 *   2. o que o preview aplica e IGUAL ao que o widget aplica? — compilando os
 *      dois SCSS e comparando declaracao a declaracao. Um grep vazio com
 *      valores errados passaria; esta segunda pergunta e que fecha a divida.
 */
const previewDir = path.resolve(
  process.cwd(),
  'app/javascript/dashboard/modules/widget-preview'
);
const widgetTokens = path.resolve(
  process.cwd(),
  'app/javascript/widget/assets/scss/_tokens.scss'
);

const arquivos = (dir, acc = []) => {
  fs.readdirSync(dir, { withFileTypes: true }).forEach(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'specs') arquivos(full, acc);
    } else {
      acc.push(full);
    }
  });
  return acc;
};

/**
 * Extrai `--nome: valor` de TODOS os blocos dos seletores dados, agrupados por
 * contexto de `@media`, com o último valor vencendo — que é o que o cascade faz.
 *
 * A versão anterior lia UM bloco só (`new RegExp(...).exec()` sem `g`), e o
 * widget declara os tokens em cinco blocos `:root` e três `.dark`. Ela media 94
 * das 131 chaves do claro e 94 das 112 do escuro, e ficava VERDE justamente
 * omitindo todos os `--w-*` — a família onde o defeito estava. O `it` logo
 * abaixo força a condição ruim e prova a diferença entre as duas leituras.
 */
const declaracoes = (cssBruto, seletores) => {
  // Comentário pode CITAR `@media` e `:root`; citar não é declarar.
  const css = cssBruto.replace(/\/\*[\s\S]*?\*\//g, '');
  const alvos = [].concat(seletores);
  const UM_MEDIA = /@media([^{]*)\{((?:[^{}]*\{[^{}]*\})*)\s*\}/g;

  const colher = trecho => {
    const acc = {};
    alvos.forEach(seletor => {
      const escapado = seletor.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      // O lookbehind impede casar `.dark` dentro de `:root.dark` ou de
      // `.wp-theme-dark` — seletor é token, não substring.
      const re = new RegExp(
        `(?<![\\w.#:%\\-\\[])${escapado}\\s*\\{([^{}]*)\\}`,
        'g'
      );
      [...trecho.matchAll(re)].forEach(bloco => {
        [...bloco[1].matchAll(/(--[\w-]+)\s*:\s*([^;]+)[;]?/g)].forEach(d => {
          acc[d[1]] = d[2].trim();
        });
      });
    });
    return acc;
  };

  const porContexto = { base: colher(css.replace(UM_MEDIA, '')) };
  [...css.matchAll(UM_MEDIA)].forEach(m => {
    const ctx = `@media${m[1].trimEnd()}`;
    const achado = colher(m[2]);
    if (Object.keys(achado).length) {
      porContexto[ctx] = { ...(porContexto[ctx] || {}), ...achado };
    }
  });
  return porContexto;
};

/* `url` aponta para o arquivo de origem, entao o `@import` relativo do SFC e
   resolvido EXATAMENTE como o vite o resolve — um caminho errado quebra aqui,
   e nao so no build. */
const compilar = (scss, origem) =>
  sass.compileString(scss, { url: pathToFileURL(origem) }).css;

const componentePath = path.join(previewDir, 'components/Widget.vue');

const estiloDoPreview = () => {
  const sfc = fs.readFileSync(componentePath, 'utf8');
  const bloco = /<style scoped lang="scss">([\s\S]*?)<\/style>/.exec(sfc);
  expect(bloco).not.toBeNull();
  return compilar(bloco[1], componentePath);
};

describe('preview do widget — os tokens são os do widget (D4)', () => {
  // DECLARAR a variável é a cópia da paleta que o D4 existe para matar;
  // CONSUMIR (`var(--slate-12)`) é o oposto — é usar a fonte única, e foi o que
  // o bloco 3.16 precisou fazer para escapar dos catch-alls `!important` do
  // skin do dashboard, que prendem qualquer classe `n-*` na cor do PAINEL.
  // O padrão exige os dois-pontos da declaração; a auto-verificação abaixo
  // prova que ele não afrouxou.
  const DECLARACAO_DE_COR = /--(?:slate|solid|iris|ruby|amber|alpha)-\w+\s*:/;

  it('o padrão de busca ainda pega uma cópia de paleta, e ignora consumo', () => {
    expect(DECLARACAO_DE_COR.test('--slate-1: 252 252 253;')).toBe(true);
    expect(DECLARACAO_DE_COR.test('  --solid-1:var(--x);')).toBe(true);
    expect(DECLARACAO_DE_COR.test('color: rgb(var(--slate-12));')).toBe(false);
  });

  it('nenhuma custom property de cor literal sobrou no preview', () => {
    const culpados = arquivos(previewDir).filter(file =>
      DECLARACAO_DE_COR.test(fs.readFileSync(file, 'utf8'))
    );

    expect(culpados).toEqual([]);
  });

  /**
   * VERMELHO ANTES DE VERDE, para a própria guarda.
   *
   * Uma asserção de igualdade entre dois mapas passa também quando os dois
   * estão pela metade — foi assim que a leitura de um bloco só ficou verde
   * omitindo os 18 `--w-*` do escuro. Aqui a condição ruim é FORÇADA: um CSS
   * com o mesmo seletor em dois blocos, mais um `@media`, mais as duas
   * armadilhas de substring que o widget tem de verdade (`:root.dark` e
   * `.wp-theme-dark` contêm `dark`).
   */
  it('a leitura varre TODOS os blocos, e não só o primeiro', () => {
    const doisBlocos = `
      .dark { --a: 1; }
      :root.dark .woot-widget-app { --nao-e-meu: 9; }
      .wp-theme-dark { --nao-e-meu: 8; }
      .dark { --b: 2; --a: 3; }
      @media (prefers-contrast: more) { .dark { --c: 4; } }
    `;
    const lido = declaracoes(doisBlocos, '.dark');

    // o 2º bloco existe (a leitura antiga parava no 1º) …
    expect(lido.base).toEqual({ '--a': '3', '--b': '2' });
    // … o último valor vence, como no cascade …
    expect(lido.base['--a']).toBe('3');
    // … o `@media` é um contexto à parte, e não some …
    expect(lido['@media (prefers-contrast: more)']).toEqual({ '--c': '4' });
    // … e `dark` como SUBSTRING de outro seletor não entra.
    expect(lido.base['--nao-e-meu']).toBeUndefined();

    // A leitura antiga, para o contraste ficar medido e não afirmado.
    const antiga = /\.dark\s*\{([^}]*)\}/.exec(doisBlocos);
    expect(Object.keys(lido.base).length).toBe(2);
    expect([...antiga[1].matchAll(/(--[\w-]+):/g)].length).toBe(1);
  });

  /*
   * O preview separa QUEM CARREGA OS TOKENS (`.wp-tokens`, que recebe por
   * estilo inline a cor real da inbox) de QUEM CARREGA O TEMA
   * (`.wp-theme-*`, no filho). No widget os dois papéis moram no mesmo
   * elemento porque lá o servidor emite regra SEM camada, que vence o
   * `@layer base`; aqui o papel de "sem camada" é do inline, e inline não
   * pode ser vencido por classe no mesmo elemento. Por isso o claro do
   * preview é comparado com os DOIS seletores somados.
   */
  it('o tema CLARO do preview é declaração a declaração o `:root` do widget', () => {
    const doWidget = declaracoes(
      compilar(fs.readFileSync(widgetTokens, 'utf8'), widgetTokens),
      ':root'
    );
    const doPreview = declaracoes(estiloDoPreview(), [
      '.wp-tokens',
      '.wp-theme-light',
    ]);

    expect(doPreview).toEqual(doWidget);
    // âncoras de valor, para o teste não passar com dois mapas vazios
    expect(doPreview.base['--slate-1']).toBe('252 252 253');
    expect(doPreview.base['--w-brand-readable']).toBe('#1d824a');
    expect(Object.keys(doPreview.base).length).toBe(131);
  });

  it('o tema ESCURO do preview é declaração a declaração o `.dark` do widget', () => {
    const doWidget = declaracoes(
      compilar(fs.readFileSync(widgetTokens, 'utf8'), widgetTokens),
      '.dark'
    );
    const doPreview = declaracoes(estiloDoPreview(), '.wp-theme-dark');

    expect(doPreview).toEqual(doWidget);
    expect(doPreview.base['--slate-1']).toBe('17 17 19');
    // O defeito do bloco 3.10, agora com asserção própria: no escuro o
    // legível reaponta para a variante escura em vez de ficar no valor claro.
    expect(doPreview.base['--w-brand-readable']).toBe(
      'var(--w-brand-readable-dark)'
    );
    expect(doPreview.base['--w-focus-ring-color']).toBe(
      'var(--w-brand-readable-dark)'
    );
    expect(Object.keys(doPreview.base).length).toBe(112);
  });

  it('o preview não declara os tokens em `:root` — isso repintaria o dashboard', () => {
    // sem os comentarios: a explicacao no topo do bloco CITA `:root`, e citar
    // nao e declarar
    const semComentarios = estiloDoPreview().replace(/\/\*[\s\S]*?\*\//g, '');

    expect(semComentarios).not.toMatch(/:root\s*\{/);
    expect(semComentarios).toMatch(/\.wp-theme-light\s*\{/);
  });
});
