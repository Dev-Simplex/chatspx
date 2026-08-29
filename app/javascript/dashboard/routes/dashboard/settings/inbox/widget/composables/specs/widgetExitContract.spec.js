import fs from 'fs';
import path from 'path';
import { DEFAULT_EXIT } from '../widgetConfigFields';
import {
  EXIT_LIMITS,
  isWhatsAppNumberValid,
  whatsAppDigits,
} from '../widgetExitContract';

/**
 * O contrato de `widget_exit` (bloco 4.08) tem DUAS pontas, e elas se separam
 * em silêncio — o mesmo defeito que `widgetAppearanceContract.spec.js` cobre
 * para a aparência.
 *
 * A autoridade é o servidor: `WidgetExitSchema` valida o jsonb e devolve 422.
 * Se a tela normalizar para um formato que o schema recusa, o administrador
 * digita um número, a tela diz que está tudo certo, e o PATCH volta 422 com um
 * "tem valor inválido em whatsapp_number" que ele não sabe o que fazer com.
 * Já aconteceu nesta base: cada trilha testava o SEU formato, e ninguém rodava
 * o payload da tela contra a validação do servidor.
 *
 * Este teste lê o arquivo Ruby de verdade.
 */
const schemaRuby = fs.readFileSync(
  path.resolve(process.cwd(), 'app/models/concerns/widget_exit_schema.rb'),
  'utf8'
);

/** `'^([0-9]{8,15})?$'` -> `{ min: 8, max: 15 }` */
const limitesDoServidor = () => {
  const pattern = /WHATSAPP_NUMBER_PATTERN\s*=\s*'([^']+)'/.exec(schemaRuby)[1];
  const [, min, max] = /\{(\d+),(\d+)\}/.exec(pattern);
  return { pattern, min: Number(min), max: Number(max) };
};

const defaultsDoServidor = () => {
  const bloco = /DEFAULTS = \{([\s\S]*?)\n {2}\}\.freeze/.exec(schemaRuby)[1];
  const pares = [...bloco.matchAll(/'([a-z_]+)' => ([^\n]+)/g)];
  return Object.fromEntries(
    pares.map(([, chave, valorCru]) => [
      chave,
      valorCru
        .trim()
        .replace(/,$/, '')
        .replace(/^'(.*)'$/, '$1'),
    ])
  );
};

describe('a tela e o servidor concordam sobre a saída do widget', () => {
  it('o arquivo do servidor foi mesmo lido — senão o teste passaria vazio', () => {
    // Sem esta âncora, um `readFileSync` de arquivo renomeado devolveria string
    // vazia e TODAS as expectativas abaixo passariam medindo nada.
    expect(schemaRuby).toContain('module WidgetExitSchema');
    expect(Object.keys(defaultsDoServidor())).toEqual(['whatsapp_number']);
  });

  it('os defaults de fábrica são os mesmos, campo a campo', () => {
    const doServidor = defaultsDoServidor();

    Object.entries(DEFAULT_EXIT).forEach(([campo, valor]) => {
      expect({ campo, valor }).toEqual({ campo, valor: doServidor[campo] });
    });
  });

  it('a tela não inventa campo que o servidor recusaria com 422', () => {
    // `additionalProperties: false` no schema: chave que a tela mandar e o
    // servidor não declarar não é ignorada — derruba o PATCH inteiro, e a tela
    // diria "salvo" com o banco intacto.
    expect(schemaRuby).toContain("'additionalProperties' => false");
    expect(
      Object.keys(DEFAULT_EXIT).filter(
        campo => !Object.keys(defaultsDoServidor()).includes(campo)
      )
    ).toEqual([]);
  });

  it('os limites que a tela mostra são os que o servidor recusa', () => {
    const { min, max } = limitesDoServidor();

    expect(EXIT_LIMITS.whatsAppNumberMin).toBe(min);
    expect(EXIT_LIMITS.whatsAppNumberMax).toBe(max);
  });

  it('o que a tela grava passa pelo padrão do servidor, e o que ela recusa não passa', () => {
    // O cruzamento que importa: a normalização da tela rodada contra a MESMA
    // expressão que o `json_schemer` vai aplicar. Comparar dois números não
    // prova que o valor gravado é aceito — só o payload contra o padrão prova.
    const doServidor = new RegExp(limitesDoServidor().pattern);

    // As duas BORDAS entram na amostra: exatamente o mínimo e exatamente o
    // máximo que a tela declara. Sem elas, um piso que se separasse (a tela em 8
    // e o servidor em 10) passaria despercebido aqui — nenhum valor de exemplo
    // cairia na faixa que os separa, e o teste diria "os dois concordam".
    const noMinimo = '9'.repeat(EXIT_LIMITS.whatsAppNumberMin);
    const noMaximo = '9'.repeat(EXIT_LIMITS.whatsAppNumberMax);

    [
      '+55 (65) 99999-8888',
      '5565999998888',
      '',
      '  ',
      'abc',
      noMinimo,
      noMaximo,
    ].forEach(digitado => {
      const gravado = whatsAppDigits(digitado);
      expect({ digitado, aceito: doServidor.test(gravado) }).toEqual({
        digitado,
        aceito: isWhatsAppNumberValid(digitado),
      });
    });

    // E as bordas são MESMO aceitas, dos dois lados — a igualdade acima também
    // valeria com os dois recusando tudo.
    expect(doServidor.test(noMinimo)).toBe(true);
    expect(doServidor.test(noMaximo)).toBe(true);

    // E a ponta que prova que o padrão não aceita tudo: curto demais e longo
    // demais são recusados nos DOIS lados.
    expect(doServidor.test('1234567')).toBe(false);
    expect(isWhatsAppNumberValid('1234567')).toBe(false);
    expect(doServidor.test('1234567890123456')).toBe(false);
    expect(isWhatsAppNumberValid('1234567890123456')).toBe(false);
  });

  it('máscara nunca chega ao banco — `wa.me` recusa o que não for dígito', () => {
    expect(whatsAppDigits('+55 (65) 99999-8888')).toBe('5565999998888');
    expect(whatsAppDigits(null)).toBe('');
    expect(whatsAppDigits(undefined)).toBe('');
  });
});
