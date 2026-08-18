import fs from 'fs';
import path from 'path';
import {
  brandTokens,
  contrastPairs,
  contrastRatio,
  formatRatio,
  isValidHex,
  luminance,
  onBrandColor,
} from '../useContrast';

/**
 * A fixture NAO foi escrita a mao nem gerada por este mesmo codigo: ela e
 * medida no Chromium por pixel de canvas (`scripts/gerar-fixture-tokens-marca.mjs`),
 * que e a implementacao de referencia da spec CSS Color 4. Comparar contra ela
 * e comparar contra o que o visitante ve — nao contra a nossa propria opiniao.
 */
const fixture = JSON.parse(
  fs.readFileSync(
    path.resolve(process.cwd(), 'spec/fixtures/widget_brand_tokens.json'),
    'utf8'
  )
);
const byBrand = hex => fixture.cores.find(c => c.brand === hex);

describe('useContrast — os numeros que a tela exibe', () => {
  it('#2DC46F como texto em fundo claro da 2,27:1 e REPROVA', () => {
    const [, brandAsTextLight] = contrastPairs('#2dc46f');

    expect(brandAsTextLight.id).toBe('brandAsTextLight');
    // toBeCloseTo(x, 2), nunca igualdade exata: o valor real e 2,273443…, e
    // igualdade por 2 casas falharia por 0,02 numa implementacao correta.
    expect(brandAsTextLight.ratio).toBeCloseTo(2.2734, 2);
    expect(brandAsTextLight.passes).toBe(false);
    expect(formatRatio(brandAsTextLight.ratio)).toBe('2,27');
  });

  it('#2DC46F reprovado como texto ganha cor ajustada que passa', () => {
    const [, brandAsTextLight] = contrastPairs('#2dc46f');

    expect(brandAsTextLight.adjustedColor).toBe('#00802f');
    expect(brandAsTextLight.adjustedRatio).toBeCloseTo(5.0863, 2);
    expect(brandAsTextLight.resolvedPasses).toBe(true);
  });

  it('#009CE0 escolhe PRETO para o texto sobre a marca, com 6,83:1', () => {
    expect(onBrandColor('#009ce0')).toBe('#000000');

    const [textOnBrand] = contrastPairs('#009ce0');
    expect(textOnBrand.color).toBe('#000000');
    expect(textOnBrand.ratio).toBeCloseTo(6.8318, 2);
    expect(textOnBrand.passes).toBe(true);
    // a escolha errada — a que a heuristica YIQ faz hoje — daria 3,07:1
    expect(contrastRatio('#009ce0', '#ffffff')).toBeCloseTo(3.0739, 2);
  });

  it('marca escura escolhe BRANCO', () => {
    expect(onBrandColor('#0b2545')).toBe('#ffffff');
    expect(luminance('#0b2545')).toBeLessThan(0.17913);
  });

  it('a borda usa o alvo de 3:1, não o de 4,5:1', () => {
    const pairs = contrastPairs('#2dc46f');
    expect(pairs[3].id).toBe('brandAsBorder');
    expect(pairs[3].target).toBe(3);
    expect(pairs[1].target).toBe(4.5);
  });

  it('hex inválido não produz par nenhum — a tela não pode calcular no vazio', () => {
    expect(isValidHex('#2dc46f')).toBe(true);
    expect(isValidHex('2dc46f')).toBe(false);
    expect(isValidHex('#zzz')).toBe(false);
    expect(contrastPairs('#zzz')).toEqual([]);
  });

  it('formata com vírgula em pt-BR e ponto em en', () => {
    expect(formatRatio(2.273443)).toBe('2,27');
    expect(formatRatio(2.273443, 'en-US')).toBe('2.27');
    expect(formatRatio(10)).toBe('10,00');
  });
});

describe('useContrast × a derivação medida no Chromium (20 cores)', () => {
  it('a fixture tem as 20 cores e o limiar declarado', () => {
    expect(fixture.cores).toHaveLength(20);
    expect(fixture.limiar_on_brand).toBe(0.17913);
  });

  /**
   * UMA divergencia conhecida, e ela esta declarada aqui em vez de escondida
   * num `toBeCloseTo` generoso: `#7c3aed` como texto no tema claro cai no canal
   * R em 115,4985 — a 0,0015 do meio do intervalo. Nos arredondamos para 115
   * (#73) e o Chromium mostra 116 (#74). Medido tambem em float32
   * (115,49854), o que descarta precisao de ponto flutuante como causa. E
   * 1/255 num canal, invisivel a olho e irrelevante para contraste; o que NAO
   * pode passar despercebido e uma segunda divergencia aparecer, ou uma
   * divergencia maior que 1/255 — e disso o teste abaixo cuida.
   */
  const EXCECAO_CONHECIDA = {
    brand: '#7c3aed',
    theme: 'light',
    token: '--w-brand-readable',
  };

  const canais = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  const deltaMaximo = (a, b) => {
    const x = canais(a);
    return Math.max(...canais(b).map((v, i) => Math.abs(v - x[i])));
  };

  it.each(fixture.cores.map(c => c.brand))(
    '%s — os 7 tokens batem nos dois temas',
    brand => {
      const esperado = byBrand(brand);

      ['light', 'dark'].forEach(theme => {
        const calculado = brandTokens(brand, theme);
        Object.entries(esperado.tokens[theme]).forEach(([token, valor]) => {
          const eExcecao =
            brand === EXCECAO_CONHECIDA.brand &&
            theme === EXCECAO_CONHECIDA.theme &&
            token === EXCECAO_CONHECIDA.token;

          if (eExcecao) {
            expect(deltaMaximo(calculado[token], valor)).toBe(1);
          } else {
            expect({ brand, theme, token, hex: calculado[token] }).toEqual({
              brand,
              theme,
              token,
              hex: valor,
            });
          }
        });
      });
    }
  );

  it('a exceção é UMA em 280 valores, e é aquela — não outra', () => {
    const divergentes = [];
    fixture.cores.forEach(({ brand, tokens }) => {
      ['light', 'dark'].forEach(theme => {
        const calculado = brandTokens(brand, theme);
        Object.entries(tokens[theme]).forEach(([token, valor]) => {
          if (calculado[token] !== valor) {
            divergentes.push({
              brand,
              theme,
              token,
              delta: deltaMaximo(calculado[token], valor),
            });
          }
        });
      });
    });

    expect(divergentes).toEqual([{ ...EXCECAO_CONHECIDA, delta: 1 }]);
  });

  it.each(fixture.cores.map(c => c.brand))(
    '%s — a luminância e as razões batem com a conta WCAG da fixture',
    brand => {
      const esperado = byBrand(brand);

      expect(luminance(brand)).toBeCloseTo(esperado.luminance, 6);
      expect(onBrandColor(brand)).toBe(esperado.on_brand);

      const pairs = contrastPairs(brand);
      expect(pairs[0].ratio).toBeCloseTo(esperado.contrast.text_on_brand, 2);
      expect(pairs[1].ratio).toBeCloseTo(
        esperado.contrast.brand_as_text_light,
        2
      );
      expect(pairs[2].ratio).toBeCloseTo(
        esperado.contrast.brand_as_text_dark,
        2
      );
      expect(pairs[3].ratio).toBeCloseTo(
        esperado.contrast.brand_as_border_light,
        2
      );
    }
  );

  it('nenhuma das 20 cores fica sem saída: o resolvido sempre passa', () => {
    fixture.cores.forEach(({ brand }) => {
      contrastPairs(brand).forEach(pair => {
        expect({ brand, id: pair.id, passes: pair.resolvedPasses }).toEqual({
          brand,
          id: pair.id,
          passes: true,
        });
      });
    });
  });
});
