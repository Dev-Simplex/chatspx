import fs from 'fs';
import path from 'path';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  SITE_KEY_BY_FIELD,
  MAX_OFFSET,
  camposSobrescritosPeloSite,
  deslocamentoDoBanco,
} from '../appearance';

/**
 * BLOCO 3.18 — A PRECEDENCIA, MEDIDA COM AS DUAS FONTES PREENCHIDAS.
 *
 * A clausula do aceite que este arquivo cobra, ao pe da letra:
 *
 *   "com `chatwootSettings.position` presente no site, o widget usa o do site
 *    E a tela avisa"
 *
 * e a metade que a torna afirmavel: SEM `chatwootSettings.position`, o widget
 * usa o do BANCO. Uma assercao so da primeira metade passaria com o defeito
 * medido intacto — o host ignorando `widgetAppearance` e usando o fallback
 * cravado ja devolve "direita" quando o site pede "direita".
 *
 * O DUBLE TEM A FORMA REAL, E ELE NAO E DIGITADO A MAO
 *
 * `channelConfig.widgetAppearance` e, byte por byte, o que
 * `Inbox#resolved_widget_appearance` produz: `DEFAULTS.merge(stored.slice(chaves))`.
 * Em vez de copiar um objeto plausivel para dentro do spec — que e como tres
 * defeitos desta base passaram por todos os testes —, `aparenciaResolvida()`
 * LE os `DEFAULTS` do arquivo Ruby e aplica a MESMA regra. Campo novo no
 * servidor entra aqui sozinho; campo renomeado quebra este arquivo.
 */
const schemaRuby = fs.readFileSync(
  path.resolve(
    process.cwd(),
    'app/models/concerns/widget_appearance_schema.rb'
  ),
  'utf8'
);

const hashRuby = nome => {
  const bloco = new RegExp(`${nome} = \\{([\\s\\S]*?)\\n {2}\\}\\.freeze`).exec(
    schemaRuby
  )[1];
  const pares = [...bloco.matchAll(/'([a-z_]+)' => ([^\n]+)/g)];
  return Object.fromEntries(
    pares.map(([, chave, cru]) => {
      const valor = cru.trim().replace(/,$/, '');
      if (valor === 'true' || valor === 'false')
        return [chave, valor === 'true'];
      if (/^\d+$/.test(valor)) return [chave, Number(valor)];
      if (/^'.*'$/.test(valor)) return [chave, valor.slice(1, -1)];
      if (/^\[\s*\](\.freeze)?$/.test(valor)) return [chave, []];
      return [chave, valor];
    })
  );
};

const DEFAULTS_DO_SERVIDOR = hashRuby('DEFAULTS');
const OVERRIDABLE_DO_SERVIDOR = hashRuby('OVERRIDABLE_BY_SITE');

/** A mesma regra de `WidgetConfigResolvable#resolved_widget_appearance`. */
const aparenciaResolvida = (gravado = {}) => {
  const permitido = Object.fromEntries(
    Object.entries(gravado).filter(([chave]) =>
      Object.keys(DEFAULTS_DO_SERVIDOR).includes(chave)
    )
  );
  return { ...DEFAULTS_DO_SERVIDOR, ...permitido };
};

describe('3.18 — o vocabulario e um so (SDK x servidor)', () => {
  it('o arquivo Ruby foi mesmo lido — senao tudo aqui passaria vazio', () => {
    expect(schemaRuby).toContain('OVERRIDABLE_BY_SITE');
    expect(Object.keys(DEFAULTS_DO_SERVIDOR).length).toBeGreaterThan(8);
    expect(Object.keys(OVERRIDABLE_DO_SERVIDOR).length).toBeGreaterThan(0);
  });

  it('`SITE_KEY_BY_FIELD` e espelho de `OVERRIDABLE_BY_SITE`, campo a campo', () => {
    // Divergir aqui e o defeito silencioso mais barato de produzir: o servidor
    // publica `panel_style`, o SDK procura outro nome, e o aviso da tela some
    // sem nada ficar vermelho.
    expect(SITE_KEY_BY_FIELD).toEqual(OVERRIDABLE_DO_SERVIDOR);
  });

  it('todo campo sobrescrivel existe nos DEFAULTS do servidor', () => {
    Object.keys(SITE_KEY_BY_FIELD).forEach(campo => {
      expect({ campo, existe: campo in DEFAULTS_DO_SERVIDOR }).toEqual({
        campo,
        existe: true,
      });
    });
  });

  it('o teto de offset do host e o mesmo `MAX_OFFSET` do servidor', () => {
    expect(MAX_OFFSET).toBe(Number(/MAX_OFFSET = (\d+)/.exec(schemaRuby)[1]));
  });
});

describe('3.18 — quais chaves de `chatwootSettings` estao ativas', () => {
  it('site mudo: nenhum campo sobrescrito', () => {
    expect(camposSobrescritosPeloSite({})).toEqual([]);
  });

  it('`position` no site aparece na lista', () => {
    expect(camposSobrescritosPeloSite({ position: 'right' })).toEqual([
      'position',
    ]);
  });

  it('`hideMessageBubble: false` E override — presenca, nao veracidade', () => {
    // O `||` que o `entrypoints/sdk.js` usava trataria isto como ausencia, e o
    // aviso da tela sumiria justamente quando as duas fontes discordam.
    expect(camposSobrescritosPeloSite({ hideMessageBubble: false })).toEqual([
      'hide_bubble',
    ]);
  });

  it('chave com `null` nao conta — e sobra de template, nao escolha', () => {
    expect(camposSobrescritosPeloSite({ position: null })).toEqual([]);
  });

  it('chave que nao e de aparencia nao entra na lista', () => {
    expect(
      camposSobrescritosPeloSite({ locale: 'pt_BR', welcomeTitle: 'Oi' })
    ).toEqual([]);
  });
});

describe('3.18 — offsets: o unico par que o site nao disputa', () => {
  it('inbox sem offset nao escreve custom property nenhuma', () => {
    expect(deslocamentoDoBanco(aparenciaResolvida())).toBeNull();
  });

  it('offset gravado vira px', () => {
    expect(deslocamentoDoBanco(aparenciaResolvida({ offset_x: 40 }))).toEqual({
      '--w-offset-x': '40px',
      '--w-offset-y': '0px',
    });
  });

  it('valor acima do teto e limitado no host, nao so no servidor', () => {
    expect(deslocamentoDoBanco({ offset_y: 5000 })['--w-offset-y']).toBe(
      `${MAX_OFFSET}px`
    );
  });
});

/**
 * O host de verdade: `entrypoints/sdk.js` inteiro, com `window.chatwootSettings`
 * como um site real o escreve, e `IFrameHelper.events.loaded` com o
 * `channelConfig` que o servidor entrega.
 */
describe('3.18 — a precedencia no boot do SDK', () => {
  let IFrameHelper;
  let enviadas;

  const bootar = async settings => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = settings;
    enviadas = [];

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    // A ORDEM IMPORTA: `resetModules` faz o entrypoint importar uma instancia
    // NOVA de `IFrameHelper`; espionar a antiga nao interceptaria nada.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
    });
  };

  const chegouOLoaded = async channelConfig => {
    if (!IFrameHelper.getAppFrame()) {
      const iframe = document.createElement('iframe');
      iframe.id = 'chatwoot_live_chat_widget';
      document.body.appendChild(iframe);
    }
    IFrameHelper.events.loaded({
      config: { authToken: 'jwt', channelConfig },
    });
    await Promise.resolve();
  };

  const holder = () => document.getElementById('cw-widget-holder');
  const mensagem = chave => enviadas.find(item => item.key === chave)?.value;

  afterEach(() => {
    vi.restoreAllMocks();
    delete window.chatwootSettings;
  });

  // ── o banco E o padrao ────────────────────────────────────────────────────
  describe('site mudo: o banco manda', () => {
    const GRAVADO = {
      position: 'left',
      theme: 'dark',
      panel_style: 'flat',
      hide_bubble: true,
      launcher_type: 'expanded_bubble',
      launcher_text: 'Falar com a Marina',
    };

    beforeEach(async () => {
      await bootar({ locale: 'pt_BR' });
      await chegouOLoaded({ widgetAppearance: aparenciaResolvida(GRAVADO) });
    }, 20000);

    it('`position` do banco vence o fallback cravado do host', () => {
      // ESTA e a assercao que estava vermelha: o host respondia 'right' porque
      // `chatwootSettings.position` era `undefined` e o ternario caia no literal.
      expect(window.$chatwoot.position).toBe('left');
    });

    it('os outros cinco campos tambem saem do banco', () => {
      expect({
        darkMode: window.$chatwoot.darkMode,
        widgetStyle: window.$chatwoot.widgetStyle,
        hideMessageBubble: window.$chatwoot.hideMessageBubble,
        type: window.$chatwoot.type,
        launcherTitle: window.$chatwoot.launcherTitle,
      }).toEqual({
        darkMode: 'dark',
        widgetStyle: 'flat',
        hideMessageBubble: true,
        type: 'expanded_bubble',
        launcherTitle: 'Falar com a Marina',
      });
    });

    it('o DOM do holder acompanha — `createFrame` ja tinha decidido errado', () => {
      // `createFrame` roda no boot, ANTES de o `channelConfig` existir: sem
      // reaplicar a classe, `window.$chatwoot.position` diria "left" e o
      // elemento continuaria com `woot-elements--right`. Duas verdades.
      expect(holder().classList.contains('woot-elements--left')).toBe(true);
      expect(holder().classList.contains('woot-elements--right')).toBe(false);
      expect(holder().classList.contains('woot-widget-holder--flat')).toBe(
        true
      );
      expect(holder().classList.contains('woot-widget--without-bubble')).toBe(
        true
      );
    });

    it('o painel recebe o valor EFETIVO no `config-set`, nao o do site', () => {
      expect(mensagem('config-set')).toMatchObject({
        position: 'left',
        darkMode: 'dark',
        widgetStyle: 'flat',
        hideMessageBubble: true,
      });
    });

    it('reporta lista VAZIA — e o que apaga um aviso que ficou velho', () => {
      expect(mensagem('appearance-overrides')).toEqual({ fields: [] });
    });
  });

  describe('offsets: o par que so o banco preenche', () => {
    it('viram custom property no holder do lancador', async () => {
      await bootar({});
      await chegouOLoaded({
        widgetAppearance: aparenciaResolvida({ offset_x: 40, offset_y: 24 }),
      });

      // Quem le estas duas variaveis e o `SDK_CSS`, e a leitura so e afirmavel
      // em navegador: `specs/browser/appearance-precedence.check.mjs` mede a
      // geometria COMPUTADA no Chromium. Aqui so se prova que o valor do banco
      // chegou ao elemento certo.
      const holderDoLancador = document.getElementById('cw-bubble-holder');
      expect(holderDoLancador.style.getPropertyValue('--w-offset-x')).toBe(
        '40px'
      );
      expect(holderDoLancador.style.getPropertyValue('--w-offset-y')).toBe(
        '24px'
      );
    }, 20000);

    it('inbox sem offset nao ganha custom property nenhuma', async () => {
      await bootar({});
      await chegouOLoaded({ widgetAppearance: aparenciaResolvida() });

      const holderDoLancador = document.getElementById('cw-bubble-holder');
      expect(holderDoLancador.style.getPropertyValue('--w-offset-x')).toBe('');
    }, 20000);
  });

  // ── as duas fontes preenchidas e DIVERGENTES ──────────────────────────────
  describe('site e banco discordam: o site vence e a tela e avisada', () => {
    beforeEach(async () => {
      await bootar({ position: 'right', darkMode: 'light' });
      await chegouOLoaded({
        widgetAppearance: aparenciaResolvida({
          position: 'left',
          theme: 'dark',
          panel_style: 'flat',
        }),
      });
    }, 20000);

    it('o widget usa o `position` do SITE', () => {
      expect(window.$chatwoot.position).toBe('right');
      expect(holder().classList.contains('woot-elements--right')).toBe(true);
    });

    it('o tema tambem e o do site', () => {
      expect(window.$chatwoot.darkMode).toBe('light');
    });

    it('o campo que o site NAO disputou continua vindo do banco', () => {
      // Precedencia e por CAMPO, nao por fonte: um `chatwootSettings` com uma
      // chave nao pode desligar a configuracao inteira da inbox.
      expect(window.$chatwoot.widgetStyle).toBe('flat');
    });

    it('reporta exatamente as chaves ativas — e o insumo do aviso da tela', () => {
      expect(mensagem('appearance-overrides')).toEqual({
        fields: ['theme', 'position'],
      });
    });
  });

  describe('`hideMessageBubble: false` explicito no site', () => {
    beforeEach(async () => {
      await bootar({ hideMessageBubble: false });
      await chegouOLoaded({
        widgetAppearance: aparenciaResolvida({ hide_bubble: true }),
      });
    }, 20000);

    it('o site vence, mesmo dizendo `false`', () => {
      expect(window.$chatwoot.hideMessageBubble).toBe(false);
    });

    it('e o campo consta como sobrescrito', () => {
      expect(mensagem('appearance-overrides')).toEqual({
        fields: ['hide_bubble'],
      });
    });
  });

  // ── degradacao ────────────────────────────────────────────────────────────
  describe('HTML antigo em cache: `channelConfig` sem `widgetAppearance`', () => {
    beforeEach(async () => {
      await bootar({ position: 'left' });
      await chegouOLoaded({ widgetColor: '#009ce0' });
    }, 20000);

    it('nada muda — o host nao inventa padrao que o servidor nao mandou', () => {
      expect(window.$chatwoot.position).toBe('left');
    });

    it('e NAO reporta: uma aba velha nao pode apagar a lista da tela', () => {
      expect(mensagem('appearance-overrides')).toBeUndefined();
    });
  });
});
