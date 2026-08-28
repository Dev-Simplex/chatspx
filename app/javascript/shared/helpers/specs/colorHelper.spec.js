import { toHex, getContrast } from 'color2k';
import * as colorHelper from 'shared/helpers/colorHelper';
import { adjustColorForContrast } from 'shared/helpers/colorHelper';

// Blocos 1.03/1.04 — `isWidgetColorLighter` foi REMOVIDA, e com ela os dois
// testes que a cobriam. O que fica no lugar não é um teste de ausência solto:
// ele nomeia a superfície inteira do módulo, então um `isWidgetColorLighter`
// que volte com o mesmo nome, ou uma irmã (`isColorLight`, `getBrightness`…),
// derruba a asserção pelo tamanho da lista, não por uma negativa que passaria
// no vácuo. A varredura por FÓRMULA — a que pega o mesmo cálculo com outro
// nome, em qualquer arquivo — está em
// `app/javascript/widget/specs/formulaDeContraste.spec.js`.
describe('a superfície exportada de colorHelper', () => {
  it('exporta exatamente adjustColorForContrast — sem heurística de brilho', () => {
    expect(Object.keys(colorHelper).sort()).toEqual(['adjustColorForContrast']);
  });
});

describe('#adjustColorForContrast', () => {
  const targetRatio = 3.1;

  const getContrastRatio = (color1, color2) => {
    // getContrast from 'color2k'
    return getContrast(color1, color2);
  };

  it('adjusts a color to meet the contrast ratio against a light background', () => {
    const color = '#ff0000';
    const backgroundColor = '#ffffff';
    const adjustedColor = adjustColorForContrast(color, backgroundColor);
    const ratio = getContrastRatio(adjustedColor, backgroundColor);

    expect(ratio).toBeGreaterThanOrEqual(targetRatio);
  });

  it('adjusts a color to meet the contrast ratio against a dark background', () => {
    const color = '#00ff00';
    const backgroundColor = '#000000';
    const adjustedColor = adjustColorForContrast(color, backgroundColor);
    const ratio = getContrastRatio(adjustedColor, backgroundColor);

    expect(ratio).toBeGreaterThanOrEqual(targetRatio);
  });

  it('returns a string representation of the color', () => {
    const color = '#00ff00';
    const backgroundColor = '#000000';
    const adjustedColor = adjustColorForContrast(color, backgroundColor);

    expect(typeof adjustedColor).toEqual('string');
  });

  it('handles cases where the color already meets the contrast ratio', () => {
    const color = '#000000';
    const backgroundColor = '#ffffff';
    const adjustedColor = adjustColorForContrast(color, backgroundColor);
    const ratio = getContrastRatio(adjustedColor, backgroundColor);

    expect(ratio).toBeGreaterThanOrEqual(targetRatio);
    expect(adjustedColor).toEqual(toHex(color));
  });

  it('does not modify a color that already exceeds the contrast ratio', () => {
    const color = '#000000';
    const backgroundColor = '#ffffff';
    const adjustedColor = adjustColorForContrast(color, backgroundColor);

    expect(adjustedColor).toEqual(toHex(color));
  });
});
