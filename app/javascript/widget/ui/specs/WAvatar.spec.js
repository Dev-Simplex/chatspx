/**
 * Mecanismo de aceite do bloco 2.01 no `WAvatar` — a metade que o lint não pega.
 *
 * `specs/primitivosLint.spec.js` garante que não sobrou literal de cor no
 * arquivo. Isso é metade: um componente pode passar no lint apontando para
 * tokens ERRADOS, e aí o lint fica verde enquanto a tela muda de cor. Como o
 * avatar aparece em três das cinco telas cobertas pelos 20 snapshots do widget,
 * "não é literal" não basta — tem de ser o MESMO valor.
 *
 * Então a tabela abaixo é o original, transcrito de `AVATAR_COLORS` antes da
 * troca, e cada asserção compara o token contra ela. Trocar um valor em
 * `_tokens_values.scss` reprova aqui antes de chegar num diff de pixel.
 */
import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import WAvatar from '../WAvatar.vue';

const TOKENS_SCSS = readFileSync(
  'app/javascript/widget/assets/scss/_tokens_values.scss',
  'utf8'
);

/** Os 26 hexadecimais que viviam dentro de `WAvatar.vue`, na ordem original. */
const ORIGINAL = {
  light: [
    ['#fbdcef', '#c2298a'],
    ['#ffe0bb', '#99543a'],
    ['#e8e8e8', '#60646c'],
    ['#ccf3ea', '#008573'],
    ['#ebebfe', '#4747c2'],
    ['#e1e9ff', '#3a5bc7'],
  ],
  dark: [
    ['#4b143d', '#ff8dcc'],
    ['#3f220d', '#ffa366'],
    ['#2a2a2a', '#adb1b8'],
    ['#023b37', '#0bd8b6'],
    ['#27264d', '#a19eff'],
    ['#1d2e62', '#9eb1ff'],
  ],
  neutro: ['#e8e8e8', '#60646c'],
};

/** Lê um mixin inteiro e devolve `{ '--w-avatar-1-bg': '#fbdcef', … }`. */
const tokensDoMixin = nome => {
  const corpo = TOKENS_SCSS.split(`@mixin ${nome} {`)[1]?.split('\n}')[0];
  if (!corpo)
    throw new Error(`mixin ${nome} não existe em _tokens_values.scss`);
  return Object.fromEntries(
    [...corpo.matchAll(/(--w-avatar-[\w-]+):\s*([^;]+);/g)].map(m => [
      m[1],
      m[2].trim(),
    ])
  );
};

const CLARO = tokensDoMixin('widget-avatar-light');
const ESCURO = tokensDoMixin('widget-avatar-dark');

const montar = props => mount(WAvatar, { props });

describe('2.01 — a paleta do avatar virou token com o MESMO valor', () => {
  it.each([1, 2, 3, 4, 5, 6])('o par %i claro é o do original', tom => {
    const [fundo, texto] = ORIGINAL.light[tom - 1];
    expect(CLARO[`--w-avatar-${tom}-bg`]).toBe(fundo);
    expect(CLARO[`--w-avatar-${tom}-fg`]).toBe(texto);
  });

  it.each([1, 2, 3, 4, 5, 6])('o par %i escuro é o do original', tom => {
    const [fundo, texto] = ORIGINAL.dark[tom - 1];
    expect(ESCURO[`--w-avatar-${tom}-bg`]).toBe(fundo);
    expect(ESCURO[`--w-avatar-${tom}-fg`]).toBe(texto);
  });

  it('o par neutro é o do original e NÃO é redeclarado no escuro', () => {
    const [fundo, texto] = ORIGINAL.neutro;
    expect(CLARO['--w-avatar-0-bg']).toBe(fundo);
    expect(CLARO['--w-avatar-0-fg']).toBe(texto);
    // Redeclarar aqui mudaria o comportamento do original, que resolvia vazio
    // no escuro e caía no valor claro. Ver a nota em `_tokens_values.scss`.
    expect(ESCURO['--w-avatar-0-bg']).toBeUndefined();
  });

  it('o `outline` de 1px é o alfa do original nos dois temas', () => {
    expect(CLARO['--w-avatar-outline']).toBe('rgb(0 0 0 / 0.03)');
    expect(ESCURO['--w-avatar-outline']).toBe('rgb(255 255 255 / 0.04)');
  });
});

describe('2.01 — o componente escolhe o mesmo tom que escolhia antes', () => {
  // `nome.length % 6` era o índice do array; o token é esse índice + 1.
  const casos = [
    ['Marina', 1],
    ['Roberto', 2],
    ['Jo', 3],
    ['Ana', 4],
    ['Caio', 5],
    ['Paulo', 6],
  ];

  it.each(casos)('%s cai no tom %i', (nome, tom) => {
    expect(nome.length % 6).toBe(tom - 1);

    const estilo = montar({ name: nome })
      .find('[role="img"]')
      .attributes('style');
    expect(estilo).toContain(`background-color: var(--w-avatar-${tom}-bg)`);
    expect(estilo).toContain(`color: var(--w-avatar-${tom}-fg)`);
  });

  it('com imagem válida nenhuma cor de iniciais é escrita', () => {
    const estilo = montar({ name: 'Ana', src: '/a.png' })
      .find('[role="img"]')
      .attributes('style');
    expect(estilo).not.toContain('--w-avatar-');
  });

  it('o mecanismo antigo de tema escuro não sobrou em lugar nenhum', () => {
    // `--dark-bg`/`--dark-text` eram custom properties escritas em `:style` e
    // aplicadas por `dark:!bg-[var(…)]` com `!important`. Quem faz isso agora é
    // a cascata; sobrar o mecanismo antigo significaria duas fontes para a mesma
    // cor, e a que vence depende da ordem — o defeito mais caro de rastrear.
    // Comentário fora: o cabeçalho do arquivo CITA o mecanismo antigo para
    // explicar por que ele saiu, e um scanner cego para comentário acusaria
    // justamente a explicação.
    const fonte = readFileSync('app/javascript/widget/ui/WAvatar.vue', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^\s*\/\/.*$/gm, '');
    expect(fonte).not.toContain('--dark-bg');
    expect(fonte).not.toContain('--dark-text');
    expect(fonte).not.toContain('!important');
  });
});
