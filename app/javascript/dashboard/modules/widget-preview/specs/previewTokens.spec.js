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

/** Extrai `--nome: valor;` de um bloco de regra, por seletor. */
const declaracoes = (css, seletor) => {
  const escapado = seletor.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const bloco = new RegExp(`${escapado}\\s*\\{([^}]*)\\}`).exec(css);
  if (!bloco) return null;
  return Object.fromEntries(
    [...bloco[1].matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(m => [
      m[1],
      m[2].trim(),
    ])
  );
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
  it('nenhuma custom property de cor literal sobrou no preview', () => {
    const culpados = arquivos(previewDir).filter(file =>
      /--slate-|--solid-|--iris-|--ruby-|--amber-|--alpha-/.test(
        fs.readFileSync(file, 'utf8')
      )
    );

    expect(culpados).toEqual([]);
  });

  it('o tema CLARO do preview é declaração a declaração o `:root` do widget', () => {
    const doWidget = declaracoes(
      compilar(fs.readFileSync(widgetTokens, 'utf8'), widgetTokens),
      ':root'
    );
    const doPreview = declaracoes(estiloDoPreview(), '.wp-theme-light');

    expect(doPreview).toEqual(doWidget);
    // uma ancora de valor, para o teste não passar com dois `null`
    expect(doPreview['--slate-1']).toBe('252 252 253');
  });

  it('o tema ESCURO do preview é declaração a declaração o `.dark` do widget', () => {
    const doWidget = declaracoes(
      compilar(fs.readFileSync(widgetTokens, 'utf8'), widgetTokens),
      '.dark'
    );
    const doPreview = declaracoes(estiloDoPreview(), '.wp-theme-dark');

    expect(doPreview).toEqual(doWidget);
    expect(doPreview['--slate-1']).toBe('17 17 19');
  });

  it('o preview não declara os tokens em `:root` — isso repintaria o dashboard', () => {
    // sem os comentarios: a explicacao no topo do bloco CITA `:root`, e citar
    // nao e declarar
    const semComentarios = estiloDoPreview().replace(/\/\*[\s\S]*?\*\//g, '');

    expect(semComentarios).not.toMatch(/:root\s*\{/);
    expect(semComentarios).toMatch(/\.wp-theme-light\s*\{/);
  });
});
