/**
 * Gera `spec/fixtures/widget_brand_tokens.json` — a referencia canonica dos 7
 * tokens de marca para 20 cores fixas.
 *
 * POR QUE MEDIR NO NAVEGADOR, e nao escrever a tabela a mao: a derivacao dos
 * tokens e uma conta de espaco de cor (OKLCH com luminosidade limitada,
 * `color-mix` em OKLab). Se a fixture fosse gerada pela MESMA implementacao que
 * o teste verifica, o teste seria tautologico: provaria apenas que a funcao
 * concorda consigo mesma. Aqui a fonte e o Chromium — a implementacao de
 * referencia da spec CSS Color 4 — lida por PIXEL renderizado num canvas, que
 * e o valor que o visitante enxerga de verdade.
 *
 * Quem consome esta fixture:
 *   - `useContrast.js` (bloco 3.08), pelo spec do dashboard;
 *   - `WidgetTokens` no servidor (bloco 1.02), que precisa produzir os MESMOS
 *     hex — e o aceite §C.3 item 10 do 23-plano-config-dashboard.
 *
 * Uso:  node scripts/gerar-fixture-tokens-marca.mjs
 */
import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

/* 20 cores: as tres do estudo (o verde do fork, o azul que a heuristica YIQ
   erra, o azul da Apple), marcas escuras, marcas quase-brancas, amarelos que
   caem fora de gamut ao serem escurecidos e cinzas sem croma. */
const CORES = [
  '#2dc46f',
  '#009ce0',
  '#e11d48',
  '#007aff',
  '#0b2545',
  '#f5a623',
  '#6b21a8',
  '#14b8a6',
  '#facc15',
  '#1e293b',
  '#dc2626',
  '#7c3aed',
  '#059669',
  '#ea580c',
  '#0ea5e9',
  '#64748b',
  '#fde047',
  '#831843',
  '#ffffff',
  '#111111',
];

/* Ponto em que uma cor tem o mesmo contraste contra branco e contra preto. */
const LIMIAR = 0.17913;
const SURFACE_LIGHT = '#ffffff';
const SURFACE_DARK = '#17171a';

const linear = channel => {
  const c = channel / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
};
const rgbOf = hex => {
  const h = hex.replace('#', '');
  return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16));
};
const luminance = hex => {
  const [r, g, b] = rgbOf(hex);
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
};
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};
const onBrand = hex => (luminance(hex) > LIMIAR ? '#000000' : '#ffffff');

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent('<canvas id="c" width="8" height="8"></canvas>');

const medido = await page.evaluate(
  ({ cores, surfaceLight, surfaceDark }) => {
    const ctx = document
      .getElementById('c')
      .getContext('2d', { willReadFrequently: true });
    const hex = value => {
      ctx.clearRect(0, 0, 8, 8);
      ctx.fillStyle = value;
      ctx.fillRect(0, 0, 8, 8);
      const [r, g, b] = ctx.getImageData(2, 2, 1, 1).data;
      return `#${[r, g, b].map(n => n.toString(16).padStart(2, '0')).join('')}`;
    };
    return cores.map(({ brand, onInv }) => ({
      brand,
      readable_light: hex(`oklch(from ${brand} min(l, 0.51) c h)`),
      readable_dark: hex(`oklch(from ${brand} max(l, 0.69) c h)`),
      border_light: hex(`oklch(from ${brand} min(l, 0.62) c h)`),
      border_dark: hex(`oklch(from ${brand} max(l, 0.58) c h)`),
      hover: hex(`color-mix(in oklab, ${brand}, ${onInv} 8%)`),
      pressed: hex(`color-mix(in oklab, ${brand}, ${onInv} 14%)`),
      subtle_light: hex(`color-mix(in oklab, ${brand} 10%, ${surfaceLight})`),
      subtle_dark: hex(`color-mix(in oklab, ${brand} 10%, ${surfaceDark})`),
    }));
  },
  {
    cores: CORES.map(brand => ({
      brand,
      // A direcao segura de deslocamento e a OPOSTA ao texto (tokens.css §1.2).
      onInv: onBrand(brand) === '#000000' ? '#ffffff' : '#000000',
    })),
    surfaceLight: SURFACE_LIGHT,
    surfaceDark: SURFACE_DARK,
  }
);
await browser.close();

const fixture = {
  gerado_por: 'scripts/gerar-fixture-tokens-marca.mjs',
  fonte: 'Chromium (Playwright), pixel de canvas — CSS Color 4',
  limiar_on_brand: LIMIAR,
  surface_light: SURFACE_LIGHT,
  surface_dark: SURFACE_DARK,
  cores: medido.map(row => {
    const on = onBrand(row.brand);
    return {
      brand: row.brand,
      luminance: luminance(row.brand),
      on_brand: on,
      contrast: {
        // 1. texto sobre a cor da marca — alvo 4,5:1
        text_on_brand: contrast(row.brand, on),
        // 2. marca como TEXTO em fundo claro — alvo 4,5:1
        brand_as_text_light: contrast(row.brand, SURFACE_LIGHT),
        // 3. marca como TEXTO em fundo escuro — alvo 4,5:1
        brand_as_text_dark: contrast(row.brand, SURFACE_DARK),
        // 4. marca como BORDA / anel de foco em fundo claro — alvo 3:1
        brand_as_border_light: contrast(row.brand, SURFACE_LIGHT),
        brand_as_border_dark: contrast(row.brand, SURFACE_DARK),
        // e o que sobra depois do ajuste, que e o que o cliente realmente ve
        readable_light_on_surface: contrast(row.readable_light, SURFACE_LIGHT),
        readable_dark_on_surface: contrast(row.readable_dark, SURFACE_DARK),
        border_light_on_surface: contrast(row.border_light, SURFACE_LIGHT),
        border_dark_on_surface: contrast(row.border_dark, SURFACE_DARK),
      },
      tokens: {
        light: {
          '--w-brand': row.brand,
          '--w-on-brand': on,
          '--w-brand-readable': row.readable_light,
          '--w-brand-border': row.border_light,
          '--w-brand-hover': row.hover,
          '--w-brand-subtle': row.subtle_light,
          '--w-focus-ring': row.border_light,
        },
        dark: {
          '--w-brand': row.brand,
          '--w-on-brand': on,
          '--w-brand-readable': row.readable_dark,
          '--w-brand-border': row.border_dark,
          '--w-brand-hover': row.hover,
          '--w-brand-subtle': row.subtle_dark,
          '--w-focus-ring': row.border_dark,
        },
      },
      pressed: row.pressed,
    };
  }),
};

const destino = path.resolve('spec/fixtures/widget_brand_tokens.json');
fs.writeFileSync(destino, `${JSON.stringify(fixture, null, 2)}\n`);
// eslint-disable-next-line no-console -- script de linha de comando: a saida E o relatorio
console.log(`${fixture.cores.length} cores medidas -> ${destino}`);
