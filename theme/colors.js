const {
  green,
  greenDark,
  yellow,
  yellowDark,
  slate,
  slateDark,
  red,
  redDark,
  violet,
  violetDark,
} = require('@radix-ui/colors');

export const colors = {
  woot: {
    25: green.green2,
    50: green.green3,
    75: green.green4,
    100: green.green5,
    200: green.green7,
    300: green.green8,
    400: greenDark.green11,
    500: greenDark.green10,
    600: greenDark.green9,
    700: greenDark.green8,
    800: greenDark.green6,
    900: greenDark.green2,
  },
  green: {
    50: greenDark.green12,
    100: green.green6,
    200: green.green7,
    300: green.green8,
    400: greenDark.green10,
    500: greenDark.green9,
    600: green.green10,
    700: green.green11,
    800: greenDark.green7,
    900: greenDark.green6,
  },
  yellow: {
    50: yellow.yellow2,
    100: yellow.yellow3,
    200: yellow.yellow5,
    300: yellowDark.yellow10,
    400: yellowDark.yellow9,
    500: yellowDark.yellow11,
    600: yellow.yellow8,
    700: yellowDark.yellow7,
    800: yellowDark.yellow2,
    900: yellowDark.yellow1,
  },
  slate: {
    25: slate.slate2,
    50: slate.slate3,
    75: slate.slate4,
    100: slate.slate5,
    200: slate.slate7,
    300: slate.slate8,
    400: slateDark.slate11,
    500: slateDark.slate10,
    600: slate.slate11,
    700: slateDark.slate8,
    800: slateDark.slate4,
    900: slateDark.slate1,
  },
  black: {
    50: slate.slate2,
    100: slateDark.slate12,
    200: slate.slate7,
    300: slate.slate8,
    400: slateDark.slate11,
    500: slate.slate9,
    600: slateDark.slate9,
    700: slateDark.slate8,
    800: slateDark.slate7,
    900: slateDark.slate2,
  },
  red: {
    50: redDark.red12,
    100: red.red6,
    200: red.red8,
    300: redDark.red11,
    400: redDark.red10,
    500: red.red9,
    600: red.red10,
    700: red.red11,
    800: redDark.red8,
    900: red.red12,
  },
  violet: {
    50: violet.violet1,
    100: violetDark.violet12,
    200: violet.violet6,
    300: violet.violet8,
    400: violet.violet11,
    500: violet.violet9,
    600: violetDark.violet8,
    700: violetDark.violet7,
    800: violetDark.violet6,
    900: violet.violet12,
  },

  // next design system color
  n: {
    slate: {
      1: 'rgb(var(--slate-1) / <alpha-value>)',
      2: 'rgb(var(--slate-2) / <alpha-value>)',
      3: 'rgb(var(--slate-3) / <alpha-value>)',
      4: 'rgb(var(--slate-4) / <alpha-value>)',
      5: 'rgb(var(--slate-5) / <alpha-value>)',
      6: 'rgb(var(--slate-6) / <alpha-value>)',
      7: 'rgb(var(--slate-7) / <alpha-value>)',
      8: 'rgb(var(--slate-8) / <alpha-value>)',
      9: 'rgb(var(--slate-9) / <alpha-value>)',
      10: 'rgb(var(--slate-10) / <alpha-value>)',
      11: 'rgb(var(--slate-11) / <alpha-value>)',
      12: 'rgb(var(--slate-12) / <alpha-value>)',
    },

    iris: {
      1: 'rgb(var(--iris-1) / <alpha-value>)',
      2: 'rgb(var(--iris-2) / <alpha-value>)',
      3: 'rgb(var(--iris-3) / <alpha-value>)',
      4: 'rgb(var(--iris-4) / <alpha-value>)',
      5: 'rgb(var(--iris-5) / <alpha-value>)',
      6: 'rgb(var(--iris-6) / <alpha-value>)',
      7: 'rgb(var(--iris-7) / <alpha-value>)',
      8: 'rgb(var(--iris-8) / <alpha-value>)',
      9: 'rgb(var(--iris-9) / <alpha-value>)',
      10: 'rgb(var(--iris-10) / <alpha-value>)',
      11: 'rgb(var(--iris-11) / <alpha-value>)',
      12: 'rgb(var(--iris-12) / <alpha-value>)',
    },

    blue: {
      1: 'rgb(var(--blue-1) / <alpha-value>)',
      2: 'rgb(var(--blue-2) / <alpha-value>)',
      3: 'rgb(var(--blue-3) / <alpha-value>)',
      4: 'rgb(var(--blue-4) / <alpha-value>)',
      5: 'rgb(var(--blue-5) / <alpha-value>)',
      6: 'rgb(var(--blue-6) / <alpha-value>)',
      7: 'rgb(var(--blue-7) / <alpha-value>)',
      8: 'rgb(var(--blue-8) / <alpha-value>)',
      9: 'rgb(var(--blue-9) / <alpha-value>)',
      10: 'rgb(var(--blue-10) / <alpha-value>)',
      11: 'rgb(var(--blue-11) / <alpha-value>)',
      12: 'rgb(var(--blue-12) / <alpha-value>)',
    },

    ruby: {
      1: 'rgb(var(--ruby-1) / <alpha-value>)',
      2: 'rgb(var(--ruby-2) / <alpha-value>)',
      3: 'rgb(var(--ruby-3) / <alpha-value>)',
      4: 'rgb(var(--ruby-4) / <alpha-value>)',
      5: 'rgb(var(--ruby-5) / <alpha-value>)',
      6: 'rgb(var(--ruby-6) / <alpha-value>)',
      7: 'rgb(var(--ruby-7) / <alpha-value>)',
      8: 'rgb(var(--ruby-8) / <alpha-value>)',
      9: 'rgb(var(--ruby-9) / <alpha-value>)',
      10: 'rgb(var(--ruby-10) / <alpha-value>)',
      11: 'rgb(var(--ruby-11) / <alpha-value>)',
      12: 'rgb(var(--ruby-12) / <alpha-value>)',
    },

    amber: {
      1: 'rgb(var(--amber-1) / <alpha-value>)',
      2: 'rgb(var(--amber-2) / <alpha-value>)',
      3: 'rgb(var(--amber-3) / <alpha-value>)',
      4: 'rgb(var(--amber-4) / <alpha-value>)',
      5: 'rgb(var(--amber-5) / <alpha-value>)',
      6: 'rgb(var(--amber-6) / <alpha-value>)',
      7: 'rgb(var(--amber-7) / <alpha-value>)',
      8: 'rgb(var(--amber-8) / <alpha-value>)',
      9: 'rgb(var(--amber-9) / <alpha-value>)',
      10: 'rgb(var(--amber-10) / <alpha-value>)',
      11: 'rgb(var(--amber-11) / <alpha-value>)',
      12: 'rgb(var(--amber-12) / <alpha-value>)',
    },

    teal: {
      1: 'rgb(var(--teal-1) / <alpha-value>)',
      2: 'rgb(var(--teal-2) / <alpha-value>)',
      3: 'rgb(var(--teal-3) / <alpha-value>)',
      4: 'rgb(var(--teal-4) / <alpha-value>)',
      5: 'rgb(var(--teal-5) / <alpha-value>)',
      6: 'rgb(var(--teal-6) / <alpha-value>)',
      7: 'rgb(var(--teal-7) / <alpha-value>)',
      8: 'rgb(var(--teal-8) / <alpha-value>)',
      9: 'rgb(var(--teal-9) / <alpha-value>)',
      10: 'rgb(var(--teal-10) / <alpha-value>)',
      11: 'rgb(var(--teal-11) / <alpha-value>)',
      12: 'rgb(var(--teal-12) / <alpha-value>)',
    },

    gray: {
      1: 'rgb(var(--gray-1) / <alpha-value>)',
      2: 'rgb(var(--gray-2) / <alpha-value>)',
      3: 'rgb(var(--gray-3) / <alpha-value>)',
      4: 'rgb(var(--gray-4) / <alpha-value>)',
      5: 'rgb(var(--gray-5) / <alpha-value>)',
      6: 'rgb(var(--gray-6) / <alpha-value>)',
      7: 'rgb(var(--gray-7) / <alpha-value>)',
      8: 'rgb(var(--gray-8) / <alpha-value>)',
      9: 'rgb(var(--gray-9) / <alpha-value>)',
      10: 'rgb(var(--gray-10) / <alpha-value>)',
      11: 'rgb(var(--gray-11) / <alpha-value>)',
      12: 'rgb(var(--gray-12) / <alpha-value>)',
    },

    violet: {
      1: 'rgb(var(--violet-1) / <alpha-value>)',
      2: 'rgb(var(--violet-2) / <alpha-value>)',
      3: 'rgb(var(--violet-3) / <alpha-value>)',
      4: 'rgb(var(--violet-4) / <alpha-value>)',
      5: 'rgb(var(--violet-5) / <alpha-value>)',
      6: 'rgb(var(--violet-6) / <alpha-value>)',
      7: 'rgb(var(--violet-7) / <alpha-value>)',
      8: 'rgb(var(--violet-8) / <alpha-value>)',
      9: 'rgb(var(--violet-9) / <alpha-value>)',
      10: 'rgb(var(--violet-10) / <alpha-value>)',
      11: 'rgb(var(--violet-11) / <alpha-value>)',
      12: 'rgb(var(--violet-12) / <alpha-value>)',
    },

    black: '#000000',
    brand: '#2dc46f',
    portal: 'var(--dynamic-portal-color)',
    'portal-soft': 'var(--dynamic-portal-color-soft)',
    'portal-faint': 'var(--dynamic-portal-color-faint)',
    background: 'rgb(var(--background-color) / <alpha-value>)',
    'input-background': 'rgba(var(--background-input-box))',
    surface: {
      1: 'rgb(var(--surface-1) / <alpha-value>)',
      2: 'rgb(var(--surface-2) / <alpha-value>)',
      active: 'rgb(var(--surface-active) / <alpha-value>)',
    },
    solid: {
      1: 'rgb(var(--solid-1) / <alpha-value>)',
      2: 'rgb(var(--solid-2) / <alpha-value>)',
      3: 'rgb(var(--solid-3) / <alpha-value>)',
      active: 'rgb(var(--solid-active) / <alpha-value>)',
      amber: 'rgb(var(--solid-amber) / <alpha-value>)',
      'amber-button': 'rgb(var(--solid-amber-button) / <alpha-value>)',
      blue: 'rgb(var(--solid-blue) / <alpha-value>)',
      'blue-2': 'rgb(var(--solid-blue-2) / <alpha-value>)',
      red: 'rgb(var(--solid-red) / <alpha-value>)',
      iris: 'rgb(var(--solid-iris) / <alpha-value>)',
      purple: 'rgb(var(--solid-purple) / <alpha-value>)',
    },
    alpha: {
      1: 'rgba(var(--alpha-1))',
      2: 'rgba(var(--alpha-2))',
      3: 'rgba(var(--alpha-3))',
      black1: 'rgba(var(--black-alpha-1))',
      black2: 'rgba(var(--black-alpha-2))',
      white: 'rgba(var(--white-alpha))',
    },
    // Voice call widget
    'call-widget': 'rgba(var(--call-widget))',
    'call-widget-border': 'rgba(var(--call-widget-border))',
    'call-widget-text': 'rgba(var(--call-widget-text))',
    'call-widget-sub-text': 'rgba(var(--call-widget-sub-text))',
    // Border colors
    weak: 'rgb(var(--border-weak) / <alpha-value>)',
    container: 'rgba(var(--border-container))',
    strong: 'rgb(var(--border-strong) / <alpha-value>)',
    'blue-strong': 'rgb(var(--border-blue-strong) / <alpha-value>)',
    'blue-border': 'rgba(var(--border-blue))',
    // Text colors
    'blue-text': 'rgb(var(--text-blue) / <alpha-value>)',
    'purple-text': 'rgb(var(--text-purple) / <alpha-value>)',
    'amber-text': 'rgb(var(--text-amber) / <alpha-value>)',
    'teal-text': 'rgb(var(--teal-11) / <alpha-value>)',
    'teal-border': 'rgb(var(--teal-9) / <alpha-value>)',
    card: 'rgb(var(--card-color) / <alpha-value>)',
    overlay: {
      default: 'rgba(var(--overlay))',
      avatar: 'rgba(var(--overlay-avatar))',
    },
    button: {
      color: 'rgb(var(--button-color) / <alpha-value>)',
      hover: 'rgb(var(--button-hover-color) / <alpha-value>)',
    },
    label: {
      color: 'rgb(var(--label-background) / <alpha-value>)',
      border: 'rgba(var(--label-border))',
    },
  },

  // ── Namespace do widget (bloco 1.04) ──────────────────────────────────────
  // ADIÇÃO, nunca substituição: a chave `n.brand` acima continua onde estava,
  // com o valor do upstream, para que `theme/colors.js` siga mergeando limpo
  // (o upstream mexe neste arquivo). O widget deixa de usar a chave dele.
  //
  // Todos os cinco valores resolvem para `var(--w-*)`, e os cinco são emitidos
  // pelo servidor em `WidgetTokens` (bloco 1.02) antes do 1º paint. Nenhum
  // token novo foi inventado aqui de propósito: um token que o servidor NÃO
  // calcula ficaria preso no fallback de `_tokens.scss` e não acompanharia a
  // cor da inbox — que é exatamente o defeito que esta onda corrige.
  //
  // Sem `<alpha-value>`: `bg-w-brand/50` não existe, e é intencional. Diluir a
  // marca com opacidade invalida o contraste calculado (regra C10 do 16 §2.5.1).
  //
  // ── Por que cada var tem fallback (nota R21) ──────────────────────────────
  // `_tokens.scss` só é carregado pelo CSS do WIDGET, mas dois componentes de
  // `shared/` que esta migração toca — `Spinner.vue` e
  // `ui/MultiselectDropdownItems.vue` — também renderizam no DASHBOARD, onde
  // nenhum `--w-*` existe. Sem o segundo argumento, `var(--w-brand-readable)`
  // ali seria guaranteed-invalid: a propriedade cai para o valor inicial e o
  // spinner do dashboard perderia a cor da marca.
  //
  // O fallback é `#2dc46f`, o literal histórico de `n.brand`, justamente para
  // que FORA do widget o resultado seja idêntico ao de antes desta migração.
  // Dentro do widget ele nunca é exercitado: `_tokens.scss` declara os sete
  // tokens no `:root`, e o servidor (1.02) os sobrescreve antes do 1º paint.
  //
  // Os fallbacks de `hover`/`active` NÃO são `#2dc46f`: são os tons derivados
  // pela mesma fórmula do serviço. Repetir a cor-base ali apagaria o feedback
  // de hover na página de survey, que também renderiza `shared/Button.vue` e
  // não carrega `_tokens.scss` — trocar `brightness-110` por uma cor igual à
  // de repouso seria uma regressão de affordance.
  w: {
    brand: {
      DEFAULT: 'var(--w-brand, #2dc46f)',
      hover: 'var(--w-brand-hover, #29b064)',
      active: 'var(--w-brand-active, #25a15b)',
      // A marca é fundo. Como texto ou ícone sobre superfície clara ela precisa
      // escurecer até 4,5:1 — este é esse valor, e serve também às bordas, que
      // pedem 3:1 (WCAG 1.4.11).
      readable: 'var(--w-brand-readable, #2dc46f)',
    },
    // Cor legível SOBRE a marca, decidida por luminância WCAG no servidor.
    'on-brand': 'var(--w-on-brand, #000000)',
    // Anel de foco. Nunca transparente — ver o comentário do `--w-focus-ring-*`
    // em `_tokens.scss`.
    focus: 'var(--w-focus-ring-color, #2dc46f)',
  },
};
