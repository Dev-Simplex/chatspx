/**
 * O medidor de contraste da tela de aparencia — e a derivacao dos 7 tokens de
 * marca que o preview usa.
 *
 * O problema que ele resolve, medido: com `widget_color = #2DC46F`, o header
 * verde com texto branco da 2,27:1. Reprova AA (4,5:1) e reprova ate o minimo
 * de componente (3:1). Hoje o cliente escolhe a cor e nao tem como saber.
 *
 * Duas regras que parecem detalhe e nao sao:
 *
 *  1. **O medidor informa, nunca impede o salvamento.** A liberdade fica na
 *     marca; a garantia fica no token. O cliente escolhe a cor dele; nos
 *     garantimos que ninguem fique com texto ilegivel.
 *  2. **Nunca `opacity` para simular estado.** Opacidade muda a luminancia e
 *     invalidaria justamente a conta que a tela esta exibindo (regra C10). Todo
 *     estado sai de `color-mix` em OKLab.
 *
 * A derivacao canonica e a do SERVIDOR (bloco 1.02). Se as duas divergirem, a
 * tela mente — por isso `specs/fixtures` guarda 20 cores medidas no Chromium e
 * o spec compara os dois lados.
 */
import { computed, unref } from 'vue';
import { getContrast, getLuminance, parseToRgba } from 'color2k';

/** Ponto em que uma cor tem o mesmo contraste contra branco e contra preto. */
export const LIMIAR_ON_BRAND = 0.17913;

export const SURFACE = Object.freeze({ light: '#ffffff', dark: '#17171a' });

/** Alvos WCAG: 4,5:1 para texto (SC 1.4.3); 3:1 para borda (SC 1.4.11). */
export const ALVO_TEXTO = 4.5;
export const ALVO_BORDA = 3;

const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

export const isValidHex = value => HEX.test(String(value ?? '').trim());

/* ---------------------------------------------------------------------------
   sRGB <-> OKLab <-> OKLCH
   Necessario porque `--w-brand-readable` e `--w-brand-border` sao a marca com a
   LUMINOSIDADE limitada, preservando croma e matiz — conta que nao existe em
   RGB. Fora do gamut sRGB o resultado e clipado por canal, que e o que o
   Chromium faz (verificado por pixel em 20 cores, `spec/fixtures`).
   ------------------------------------------------------------------------ */
const srgbToLinear = c =>
  c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
const linearToSrgb = c =>
  c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;

const toRgbUnit = hex =>
  parseToRgba(hex)
    .slice(0, 3)
    .map(v => v / 255);

const toHex = rgb =>
  `#${rgb
    .map(v =>
      Math.round(Math.min(1, Math.max(0, v)) * 255)
        .toString(16)
        .padStart(2, '0')
    )
    .join('')}`;

const rgbToOklab = ([r, g, b]) => {
  const R = srgbToLinear(r);
  const G = srgbToLinear(g);
  const B = srgbToLinear(b);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
};

const oklabToRgb = ([L, a, b]) => {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ].map(linearToSrgb);
};

const labToLch = ([L, a, b]) => [
  L,
  Math.hypot(a, b),
  (Math.atan2(b, a) * 180) / Math.PI,
];
const lchToLab = ([L, C, H]) => [
  L,
  C * Math.cos((H * Math.PI) / 180),
  C * Math.sin((H * Math.PI) / 180),
];

/** A marca com a luminosidade limitada — croma e matiz preservados. */
export const withLightness = (hex, limit) => {
  const [L, C, H] = labToLch(rgbToOklab(toRgbUnit(hex)));
  return toHex(oklabToRgb(lchToLab([limit(L), C, H])));
};

/** `color-mix(in oklab, a, b weight)` — mistura, nunca opacidade (C10). */
export const mixOklab = (hexA, hexB, weightB) => {
  const a = rgbToOklab(toRgbUnit(hexA));
  const b = rgbToOklab(toRgbUnit(hexB));
  return toHex(oklabToRgb(a.map((v, i) => v * (1 - weightB) + b[i] * weightB)));
};

export const luminance = hex => getLuminance(hex);
export const contrastRatio = (a, b) => getContrast(a, b);

/**
 * A cor do texto sobre a marca. Preto PURO, nao um cinza-quase-preto: com
 * `#000000` a zona morta (cores em que nenhuma das duas escolhas atinge 4,5:1)
 * e 0,00%; com `#111111` sao 3,42%.
 */
export const onBrandColor = hex =>
  getLuminance(hex) > LIMIAR_ON_BRAND ? '#000000' : '#ffffff';

/**
 * Os 7 tokens de marca de um tema. Mesma derivacao de `shared/tokens.css` §1.2
 * — e a mesma que o servidor tem de produzir (bloco 1.02).
 */
export const brandTokens = (hex, theme = 'light') => {
  const surface = SURFACE[theme] ?? SURFACE.light;
  const on = onBrandColor(hex);
  // A direcao segura de deslocamento e a OPOSTA ao texto: misturar rumo ao
  // texto (que e o que o Material 3 faz) derruba 16,3% das cores abaixo de
  // 4,5:1 no hover, porque aqui a cor e arbitraria — quem escolhe e o cliente.
  const away = on === '#000000' ? '#ffffff' : '#000000';
  const readable =
    theme === 'dark'
      ? withLightness(hex, L => Math.max(L, 0.69))
      : withLightness(hex, L => Math.min(L, 0.51));
  const border =
    theme === 'dark'
      ? withLightness(hex, L => Math.max(L, 0.58))
      : withLightness(hex, L => Math.min(L, 0.62));

  return {
    '--w-brand': hex,
    '--w-on-brand': on,
    '--w-brand-readable': readable,
    '--w-brand-border': border,
    '--w-brand-hover': mixOklab(hex, away, 0.08),
    '--w-brand-subtle': mixOklab(hex, surface, 0.9),
    '--w-focus-ring': border,
  };
};

/** O estado `pressed`, irmao do hover — 14% na mesma direcao. */
export const brandPressed = hex =>
  mixOklab(hex, onBrandColor(hex) === '#000000' ? '#ffffff' : '#000000', 0.14);

export const PAIR_IDS = Object.freeze([
  'textOnBrand',
  'brandAsTextLight',
  'brandAsTextDark',
  'brandAsBorder',
]);

/**
 * Os quatro pares que a tela exibe. Cada um traz o que a cor CRUA faz, se isso
 * passa, e — quando nao passa — a cor ajustada que o widget vai usar no lugar,
 * com a razao dela. E o que separa "informar" de "reclamar".
 */
export const contrastPairs = hex => {
  if (!isValidHex(hex)) return [];

  const on = onBrandColor(hex);
  const light = brandTokens(hex, 'light');
  const dark = brandTokens(hex, 'dark');

  const pair = (id, { fg, bg, target, adjusted }) => {
    const rawRatio = getContrast(fg, bg);
    const adjustedRatio = adjusted ? getContrast(adjusted, bg) : null;
    const wasAdjusted =
      Boolean(adjusted) && adjusted.toLowerCase() !== fg.toLowerCase();
    return {
      id,
      target,
      color: fg,
      background: bg,
      ratio: rawRatio,
      passes: rawRatio >= target,
      adjustedColor: wasAdjusted ? adjusted : null,
      adjustedRatio: wasAdjusted ? adjustedRatio : null,
      // Verdito da LINHA: com ajuste, o que o visitante ve e a cor ajustada.
      resolvedRatio: wasAdjusted ? adjustedRatio : rawRatio,
      resolvedPasses: (wasAdjusted ? adjustedRatio : rawRatio) >= target,
    };
  };

  return [
    // 1. Texto sobre a cor da marca — quem escolhe e o algoritmo, nunca o
    //    cliente; por isso este par nunca "ajusta": ele ja nasce resolvido.
    pair('textOnBrand', { fg: on, bg: hex, target: ALVO_TEXTO }),
    // 2 e 3. A marca COMO TEXTO, nos dois fundos.
    pair('brandAsTextLight', {
      fg: hex,
      bg: SURFACE.light,
      target: ALVO_TEXTO,
      adjusted: light['--w-brand-readable'],
    }),
    pair('brandAsTextDark', {
      fg: hex,
      bg: SURFACE.dark,
      target: ALVO_TEXTO,
      adjusted: dark['--w-brand-readable'],
    }),
    // 4. A marca como borda / anel de foco, no fundo mais dificil (o claro).
    pair('brandAsBorder', {
      fg: hex,
      bg: SURFACE.light,
      target: ALVO_BORDA,
      adjusted: light['--w-brand-border'],
    }),
  ];
};

/** `2.273443` -> `2,27` em pt-BR, `2.27` em en. Duas casas, sempre. */
export const formatRatio = (ratio, locale = 'pt-BR') =>
  new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(ratio);

export function useContrast(brandColor, theme = 'light') {
  const hex = computed(() => String(unref(brandColor) ?? '').trim());
  return {
    isValid: computed(() => isValidHex(hex.value)),
    pairs: computed(() => contrastPairs(hex.value)),
    tokens: computed(() =>
      isValidHex(hex.value) ? brandTokens(hex.value, unref(theme)) : {}
    ),
    onBrand: computed(() =>
      isValidHex(hex.value) ? onBrandColor(hex.value) : '#000000'
    ),
  };
}
