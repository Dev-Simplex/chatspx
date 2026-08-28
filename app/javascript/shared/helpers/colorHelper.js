import { toHex, mix, getLuminance, getContrast } from 'color2k';

// ─────────────────────────────────────────────────────────────────────────────
// AQUI VIVIA `isWidgetColorLighter` — blocos 1.03/1.04.
//
// Era brilho ponderado `(r*299 + g*587 + b*114) / 1000 > 225`: a fórmula do
// YIQ da televisão analógica, não WCAG. Ela não mede razão de contraste
// nenhuma, e por isso o widget e o lançador chegavam a decisões diferentes
// sobre a MESMA cor de inbox — o header dizia "esta marca é escura" e o
// lançador dizia "é clara".
//
// Quem decide contraste agora é o SERVIDOR, uma vez, por luminância WCAG
// (`WidgetTokens`, bloco 1.02): ele emite `--w-on-brand` (o legível SOBRE a
// marca) e `--w-brand-readable` (a marca escurecida até 4,5:1 para virar texto
// ou ícone). O front consome token; não recalcula.
//
// O aceite do 1.03 é literalmente "nenhuma fórmula de contraste em JS", e
// `specs/formulaDeContraste.spec.js` varre `widget/`, `sdk/` e `shared/` para
// que ela não volte por outro nome.
// ─────────────────────────────────────────────────────────────────────────────

export const adjustColorForContrast = (color, backgroundColor) => {
  const targetRatio = 3.1;
  const MAX_ITERATIONS = 20;
  let adjustedColor = color;

  for (let iteration = 0; iteration < MAX_ITERATIONS; iteration += 1) {
    const currentRatio = getContrast(adjustedColor, backgroundColor);
    if (currentRatio >= targetRatio) {
      break;
    }
    const adjustmentDirection =
      getLuminance(adjustedColor) < 0.5 ? '#fff' : '#151718';
    adjustedColor = mix(adjustedColor, adjustmentDirection, 0.05);
  }

  return toHex(adjustedColor);
};
