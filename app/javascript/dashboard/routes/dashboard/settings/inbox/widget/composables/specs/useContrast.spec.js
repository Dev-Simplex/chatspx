import fs from 'fs';
import path from 'path';
import {
  ALVO_TEXTO,
  brandTokens,
  contrastPairs,
  contrastRatio,
  formatRatio,
  isValidHex,
  LIMIAR_ON_BRAND,
  luminance,
  onBrandColor,
  readableOn,
  SURFACE,
} from '../useContrast';

/**
 * A fixture NAO foi escrita a mao nem gerada por este mesmo codigo: ela sai do
 * SERVIDOR — `WidgetTokens` (Ruby), o mesmo objeto que escreve o `<style>` do
 * widget em producao — por `scripts/gerar-fixture-tokens-marca.rb`. E o
 * cruzamento que o aceite pede: a derivacao canonica e a do servidor, e a tela
 * mente se calcular diferente dele.
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

    expect(brandAsTextLight.adjustedColor).toBe('#1d824a');
    expect(brandAsTextLight.adjustedRatio).toBeCloseTo(4.8341, 2);
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

  it('as constantes da tela sao as que a fixture declara, nao um par paralelo', () => {
    // O limiar e o alvo tambem atravessam os dois lados. Comparar o valor do
    // MODULO com o da fixture (e nao com um literal repetido aqui) e o que faz
    // uma mudanca no servidor chegar como falha em vez de como divergencia
    // silenciosa — foi por falta desse elo que `SURFACE.dark` ficou dois blocos
    // apontando para o fundo do painel enquanto o servidor ja usava o balao.
    expect(LIMIAR_ON_BRAND).toBe(fixture.limiar_on_brand);
    expect(ALVO_TEXTO).toBe(fixture.alvo_texto);
  });

  it.each(fixture.cores.map(c => c.brand))(
    '%s — os 7 tokens do servidor batem hex a hex',
    brand => {
      const esperado = fixture.cores.find(c => c.brand === brand);

      expect(brandTokens(brand)).toEqual(esperado.tokens);
    }
  );

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
      // o par 4 mede a MESMA cor contra o mesmo fundo do par 2 — o que muda e
      // o alvo (3:1 em vez de 4,5:1), porque borda nao e texto
      expect(pairs[3].ratio).toBeCloseTo(
        esperado.contrast.brand_as_text_light,
        2
      );
    }
  );

  it('a superfície escura da tela é a MESMA do servidor', () => {
    expect(SURFACE.dark).toBe(fixture.surface_dark);
    expect(SURFACE.light).toBe(fixture.surface_light);
  });

  it('a superfície escura é o BALÃO do agente (#2c2d36), não o fundo do painel', () => {
    // A defasagem que existiu, escrita como teste. Enquanto a tela media contra
    // `#121213` (o painel) e o servidor ja media contra `#2c2d36` (o balao, onde
    // o link e de fato pintado), o medidor exibia numeros que o widget nao ia
    // produzir: regenerando a fixture pelo gerador oficial, 20 de 20 cores
    // divergiam e 13 tokens hex mudavam.
    expect(SURFACE.dark).toBe('#2c2d36');

    // A condicao RUIM, FORCADA — sem isso a assercao passaria tambem num mundo
    // em que a diferenca entre as duas superficies nao muda nada: calibrar
    // contra o painel deixa a cor ABAIXO de 4,5:1 quando ela chega ao balao.
    const painel = '#121213';
    expect(
      contrastRatio(readableOn('#009ce0', painel), SURFACE.dark)
    ).toBeCloseTo(4.4486, 2);
    expect(
      contrastRatio(readableOn('#1f93ff', painel), SURFACE.dark)
    ).toBeCloseTo(4.347, 2);

    // E a cor calibrada contra o balao cruza — inclusive `#1f93ff`, que e o
    // DEFAULT de `channel_web_widgets`, ou seja, a inbox que ninguem configurou.
    expect(
      contrastRatio(readableOn('#009ce0', SURFACE.dark), SURFACE.dark)
    ).toBeCloseTo(4.697, 2);
    expect(
      contrastRatio(readableOn('#1f93ff', SURFACE.dark), SURFACE.dark)
    ).toBeCloseTo(4.5801, 2);
  });

  it.each(fixture.cores.map(c => c.brand))(
    '%s — o texto ajustado alcança 4,5:1 nos dois temas, como no servidor',
    brand => {
      const esperado = fixture.cores.find(c => c.brand === brand);

      expect(
        contrastRatio(readableOn(brand, SURFACE.light), SURFACE.light)
      ).toBeCloseTo(esperado.contrast.readable_light_on_surface, 2);
      expect(
        contrastRatio(readableOn(brand, SURFACE.dark), SURFACE.dark)
      ).toBeCloseTo(esperado.contrast.readable_dark_on_surface, 2);
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
