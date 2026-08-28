/**
 * O medidor de contraste da tela de aparencia.
 *
 * O problema que ele resolve, medido: com `widget_color = #2DC46F`, o header
 * verde com texto branco da 2,27:1. Reprova AA (4,5:1) e reprova ate o minimo
 * de componente (3:1). Hoje o cliente escolhe a cor e nao tem como saber.
 *
 * ── A DERIVACAO CANONICA E A DO SERVIDOR ──────────────────────────────────
 * Quem calcula os tokens que o widget usa e `WidgetTokens`
 * (`app/services/widget_tokens.rb`, bloco 1.02): ele escreve o `<style>` do
 * `show.html.erb` antes do primeiro paint e manda os mesmos valores ao launcher
 * pela ponte. Este arquivo NAO inventa uma segunda derivacao — ele reproduz
 * aquela, para a tela poder MOSTRAR de antemao o que o servidor vai fazer. Se
 * os dois divergirem, a tela mente para o cliente; por isso
 * `spec/fixtures/widget_brand_tokens.json` e gerado pelo Ruby e o spec do
 * dashboard compara os dois lados em 20 cores.
 *
 * Consequencia pratica, e ela importa para quem for mexer aqui: a mistura e em
 * **RGB**, em passos de 5%, ate cruzar 4,5:1 — nao e o `oklch(from … min(l,.51))`
 * do `plano/redesenho/shared/tokens.css`. Aquele arquivo e a fundacao dos
 * mockups; o produto e o que o servidor emite.
 *
 * Duas regras que parecem detalhe e nao sao:
 *   1. **O medidor informa, nunca impede o salvamento.** A liberdade fica na
 *      marca; a garantia fica no token.
 *   2. **Nunca `opacity` para simular estado** (regra C10): opacidade muda a
 *      luminancia e invalidaria justamente a conta que a tela esta exibindo.
 */
import { computed, unref } from 'vue';
import { getContrast, getLuminance, parseToRgba } from 'color2k';

/* Os numeros abaixo sao os de `WidgetTokens`. Mudar um sem mudar o outro lado
   quebra o spec que cruza as 20 cores — que e o ponto. */

/** Ponto em que uma cor tem o mesmo contraste contra branco e contra preto. */
export const LIMIAR_ON_BRAND = 0.17913;

/**
 * As duas superficies do widget — os MESMOS valores de
 * `WidgetTokens::SURFACE_LIGHT` e `WidgetTokens::SURFACE_DARK`.
 *
 * ⚠️ A escura e o BALAO DO AGENTE (`--solid-3: 44 45 54` = `#2c2d36`), nao o
 * fundo do painel (`#121213`). A diferenca nao e estetica: `--w-brand-readable-
 * dark` pinta o link DENTRO do balao, e uma cor calibrada contra o painel chega
 * ao balao abaixo do alvo — `#009CE0` da 4,4486:1 e `#1F93FF`, que e o DEFAULT
 * de `channel_web_widgets`, da 4,3470:1. Calibrando contra o balao os dois
 * cruzam (4,6970 e 4,5801). Este arquivo tinha `#121213` enquanto o servidor ja
 * usava `#2c2d36`: o medidor exibia numeros que o widget nao ia produzir.
 *
 * Quem trava as duas pontas:
 *   · `spec/services/widget_brand_tokens_fixture_spec.rb` falha se a fixture
 *     nao for mais o que `WidgetTokens` deriva hoje;
 *   · `specs/useContrast.spec.js` falha se ESTE arquivo divergir da fixture.
 * Mexer num lado so deixa um dos dois vermelho — que e o ponto.
 */
export const SURFACE = Object.freeze({ light: '#ffffff', dark: '#2c2d36' });

/** Alvos WCAG: 4,5:1 para texto (SC 1.4.3); 3:1 para borda (SC 1.4.11). */
export const ALVO_TEXTO = 4.5;
export const ALVO_BORDA = 3;

const READABLE_STEP = 0.05;
const READABLE_MAX_STEPS = 20;
const HOVER_MIX = 0.1;
const ACTIVE_MIX = 0.18;

const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

export const isValidHex = value => HEX.test(String(value ?? '').trim());

const toRgb = hex => parseToRgba(hex).slice(0, 3);

const toHex = rgb =>
  `#${rgb
    .map(channel =>
      Math.round(Math.min(255, Math.max(0, channel)))
        .toString(16)
        .padStart(2, '0')
    )
    .join('')}`;

/**
 * Mistura em RGB, com arredondamento por canal — a mesma de `WidgetTokens.mix`.
 * O arredondamento a cada passo NAO e descuido: `readable_on` itera sobre a cor
 * ja arredondada, e reproduzir isso e o que faz os dois lados cairem no mesmo
 * hex em vez de num vizinho.
 */
export const mix = (colorA, colorB, amount) => {
  const a = toRgb(colorA);
  const b = toRgb(colorB);
  return toHex(a.map((channel, i) => channel + (b[i] - channel) * amount));
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
 * A marca como TEXTO sobre uma superficie: caminha 5% por vez na direcao que
 * afasta da superficie, ate cruzar o alvo. Se a cor ja cruza, volta intacta —
 * a marca do cliente so e alterada quando ela seria ilegivel.
 */
export const readableOn = (brand, surface, target = ALVO_TEXTO) => {
  const direction = onBrandColor(surface);
  let color = brand;
  for (let step = 0; step < READABLE_MAX_STEPS; step += 1) {
    if (getContrast(color, surface) >= target) break;
    color = mix(color, direction, READABLE_STEP);
  }
  return color;
};

/**
 * Os tokens de marca, com os MESMOS nomes que `WidgetTokens#root_tokens` emite
 * — o que permite comparar chave a chave em vez de por posicao.
 */
export const brandTokens = hex => {
  const normalized = String(hex).trim().toLowerCase();
  const on = onBrandColor(normalized);
  const readable = readableOn(normalized, SURFACE.light);
  const readableDark = readableOn(normalized, SURFACE.dark);

  return {
    '--w-brand': normalized,
    '--w-brand-hover': mix(normalized, on, HOVER_MIX),
    '--w-brand-active': mix(normalized, on, ACTIVE_MIX),
    '--w-on-brand': on,
    '--w-brand-readable': readable,
    '--w-brand-readable-dark': readableDark,
    '--w-focus-ring-color': readable,
  };
};

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

  const normalized = String(hex).trim().toLowerCase();
  const tokens = brandTokens(normalized);

  const pair = (id, { fg, bg, target, adjusted }) => {
    const rawRatio = getContrast(fg, bg);
    const wasAdjusted =
      Boolean(adjusted) && adjusted.toLowerCase() !== fg.toLowerCase();
    const adjustedRatio = wasAdjusted ? getContrast(adjusted, bg) : null;
    const resolvedRatio = wasAdjusted ? adjustedRatio : rawRatio;

    return {
      id,
      target,
      color: fg,
      background: bg,
      ratio: rawRatio,
      passes: rawRatio >= target,
      adjustedColor: wasAdjusted ? adjusted : null,
      adjustedRatio,
      // Veredito da LINHA: com ajuste, o que o visitante ve e a cor ajustada.
      resolvedRatio,
      resolvedPasses: resolvedRatio >= target,
    };
  };

  return [
    // 1. Texto sobre a cor da marca — quem escolhe e o algoritmo, nunca o
    //    cliente; por isso este par nunca "ajusta": ele ja nasce resolvido.
    pair('textOnBrand', {
      fg: tokens['--w-on-brand'],
      bg: normalized,
      target: ALVO_TEXTO,
    }),
    // 2 e 3. A marca COMO TEXTO, nos dois fundos.
    pair('brandAsTextLight', {
      fg: normalized,
      bg: SURFACE.light,
      target: ALVO_TEXTO,
      adjusted: tokens['--w-brand-readable'],
    }),
    pair('brandAsTextDark', {
      fg: normalized,
      bg: SURFACE.dark,
      target: ALVO_TEXTO,
      adjusted: tokens['--w-brand-readable-dark'],
    }),
    // 4. A marca como borda e anel de foco, no fundo mais dificil (o claro).
    //    O anel de foco do widget usa `--w-focus-ring-color`, que e o readable.
    pair('brandAsBorder', {
      fg: normalized,
      bg: SURFACE.light,
      target: ALVO_BORDA,
      adjusted: tokens['--w-focus-ring-color'],
    }),
  ];
};

/** `2.273443` -> `2,27` em pt-BR, `2.27` em en. Duas casas, sempre. */
export const formatRatio = (ratio, locale = 'pt-BR') =>
  new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(ratio);

export function useContrast(brandColor) {
  const hex = computed(() => String(unref(brandColor) ?? '').trim());
  return {
    isValid: computed(() => isValidHex(hex.value)),
    pairs: computed(() => contrastPairs(hex.value)),
    tokens: computed(() =>
      isValidHex(hex.value) ? brandTokens(hex.value) : {}
    ),
    onBrand: computed(() =>
      isValidHex(hex.value) ? onBrandColor(hex.value) : '#000000'
    ),
  };
}
