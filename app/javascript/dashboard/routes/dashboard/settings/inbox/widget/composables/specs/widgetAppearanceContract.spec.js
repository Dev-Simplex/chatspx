import fs from 'fs';
import path from 'path';
import {
  DEFAULT_APPEARANCE,
  WIDGET_CONFIG_FIELDS,
} from '../widgetConfigFields';
import {
  APPEARANCE_LIMITS,
  APPEARANCE_ENUMS,
} from '../widgetAppearanceContract';

/**
 * O contrato da aparência tem DUAS pontas, e elas se separam em silêncio.
 *
 * O servidor (bloco 3.18, `WidgetAppearanceSchema`) é a autoridade: ele valida
 * o jsonb e devolve 422. A tela existe para mostrar de antemão o que o servidor
 * vai fazer — se ela usa outro default, outro teto ou outro enum, ela mente:
 * exibe "20 px" onde o valor efetivo é 0, recusa um offset que o servidor
 * aceitaria, ou avisa "máximo 40 caracteres" quando cabem 64.
 *
 * Este teste lê o arquivo Ruby de verdade. Não é elegante, e é justamente o
 * ponto: qualquer mudança de um lado só falha aqui, nomeando o campo.
 */
const schemaRuby = fs.readFileSync(
  path.resolve(
    process.cwd(),
    'app/models/concerns/widget_appearance_schema.rb'
  ),
  'utf8'
);

const constanteNumerica = nome =>
  Number(new RegExp(`${nome}\\s*=\\s*(\\d+)`).exec(schemaRuby)?.[1]);

const constanteLista = nome =>
  new RegExp(`${nome}\\s*=\\s*%w\\[([^\\]]+)\\]`)
    .exec(schemaRuby)?.[1]
    .trim()
    .split(/\s+/);

const defaultsDoServidor = () => {
  const bloco = /DEFAULTS = \{([\s\S]*?)\n {2}\}\.freeze/.exec(schemaRuby)[1];
  // sem exigir `\n` no fim: a ÚLTIMA entrada do hash Ruby não tem quebra
  // depois dela, e era assim que `home_intents` sumia da leitura
  const pares = [...bloco.matchAll(/'([a-z_]+)' => ([^\n]+)/g)];
  return Object.fromEntries(
    pares.map(([, chave, valorCru]) => {
      const valor = valorCru.trim().replace(/,$/, '');
      if (valor === 'true' || valor === 'false')
        return [chave, valor === 'true'];
      if (/^\d+$/.test(valor)) return [chave, Number(valor)];
      if (/^'.*'$/.test(valor)) return [chave, valor.slice(1, -1)];
      // `[].freeze` no Ruby é a lista vazia — o `.freeze` é ruído para nós
      if (/^\[\s*\](\.freeze)?$/.test(valor)) return [chave, []];
      return [chave, valor];
    })
  );
};

const strongParams = fs.readFileSync(
  path.resolve(
    process.cwd(),
    'app/controllers/api/v1/accounts/inboxes_controller.rb'
  ),
  'utf8'
);

describe('o PATCH que a tela monta é o que o controller aceita', () => {
  it.each(WIDGET_CONFIG_FIELDS.filter(f => f.scope === 'additional'))(
    '`$path` está no strong params da inbox',
    field => {
      // Uma chave que a tela envia e o `permit` não conhece é descartada em
      // SILÊNCIO: a tela mostra "salvo", o banco não muda, e o administrador só
      // descobre ao recarregar. É o defeito mais caro desta superfície.
      expect(strongParams).toMatch(new RegExp(`${field.path}(:|\\s|,|\\})`));
    }
  );

  it('o sub-hash `channel` também é aceito', () => {
    expect(strongParams).toMatch(/channel:/);
  });
});

describe('a tela e o servidor concordam sobre a aparência', () => {
  it('o arquivo do servidor foi mesmo lido — senão o teste passaria vazio', () => {
    expect(schemaRuby).toContain('module WidgetAppearanceSchema');
    expect(Object.keys(defaultsDoServidor()).length).toBeGreaterThan(8);
  });

  it('os defaults de fábrica são os mesmos, campo a campo', () => {
    const doServidor = defaultsDoServidor();

    Object.entries(DEFAULT_APPEARANCE).forEach(([campo, valor]) => {
      expect({ campo, valor }).toEqual({ campo, valor: doServidor[campo] });
    });
  });

  it('os tetos que a tela mostra são os que o servidor recusa', () => {
    expect(APPEARANCE_LIMITS.offsetMax).toBe(constanteNumerica('MAX_OFFSET'));
    expect(APPEARANCE_LIMITS.launcherTextMax).toBe(
      constanteNumerica('MAX_LAUNCHER_TEXT')
    );
    expect(APPEARANCE_LIMITS.offsetMin).toBe(0);
  });

  it('os enums que a tela oferece são os que o servidor aceita', () => {
    expect(APPEARANCE_ENUMS.theme).toEqual(constanteLista('THEMES'));
    expect(APPEARANCE_ENUMS.position).toEqual(constanteLista('POSITIONS'));
    expect(APPEARANCE_ENUMS.launcher_type).toEqual(
      constanteLista('LAUNCHER_TYPES')
    );
    expect(APPEARANCE_ENUMS.panel_style).toEqual(
      constanteLista('PANEL_STYLES')
    );
  });

  it('a tela não inventa campo que o servidor descartaria', () => {
    const doServidor = Object.keys(defaultsDoServidor());

    expect(
      Object.keys(DEFAULT_APPEARANCE).filter(
        campo => !doServidor.includes(campo)
      )
    ).toEqual([]);
  });
});
