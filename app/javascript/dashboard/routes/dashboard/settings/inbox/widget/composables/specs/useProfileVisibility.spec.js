import { ref } from 'vue';
import {
  DEFAULT_PROFILE,
  PROFILE_PROPOSALS,
  TRIGGER_PRESETS,
  currentValuesFromDraft,
  hiddenSectionsFor,
  keptValues,
  normalizeProfile,
  otherProfile,
  pendingProposals,
  profileWrites,
  triggersPresetOf,
  useProfileVisibility,
} from '../useProfileVisibility';
import { RECOMMENDED_TRIGGERS } from '../widgetTriggersContract';

describe('normalizeProfile', () => {
  it('nil é lido como support — é o comportamento de hoje, e não há backfill', () => {
    expect(normalizeProfile(undefined)).toBe('support');
    expect(normalizeProfile(null)).toBe('support');
    expect(normalizeProfile('')).toBe('support');
    expect(DEFAULT_PROFILE).toBe('support');
  });

  it('valor fora do enum não vira marketing por acidente', () => {
    expect(normalizeProfile('vendas')).toBe('support');
    expect(normalizeProfile('marketing')).toBe('marketing');
  });

  it('o outro perfil é o outro', () => {
    expect(otherProfile('support')).toBe('marketing');
    expect(otherProfile('marketing')).toBe('support');
  });
});

describe('useProfileVisibility', () => {
  it('suporte esconde gatilhos e tracking; marketing esconde CSAT e NPS', () => {
    expect(hiddenSectionsFor('support')).toEqual([
      'appearance.launcherExpanded',
      'triggers',
      'triggers.segmentation',
      'prechat.builder',
      'prechat.incompleteLead',
      'tracking',
    ]);
    expect(hiddenSectionsFor('marketing')).toEqual(['csat', 'nps']);
  });

  it('seção fora da matriz aparece nos dois perfis', () => {
    const { isSectionVisible } = useProfileVisibility(ref('support'));

    expect(isSectionVisible('appearance.brandColor')).toBe(true);
    expect(isSectionVisible('prechat.masks')).toBe(true);
  });

  it('o perfil ESCONDE, não remove: o link de escape traz a seção de volta', () => {
    const { isSectionVisible, showOtherProfile, toggleOtherProfile } =
      useProfileVisibility(ref('support'));

    expect(isSectionVisible('triggers')).toBe(false);

    toggleOtherProfile();

    expect(showOtherProfile.value).toBe(true);
    expect(isSectionVisible('triggers')).toBe(true);
    // e o que já era visível continua visível
    expect(isSectionVisible('csat')).toBe(true);
  });

  it('acompanha a troca de perfil sem remontar', () => {
    const profile = ref('support');
    const { isSectionVisible, activeProfile } = useProfileVisibility(profile);

    expect(isSectionVisible('csat')).toBe(true);

    profile.value = 'marketing';

    expect(activeProfile.value).toBe('marketing');
    expect(isSectionVisible('csat')).toBe(false);
    expect(isSectionVisible('triggers')).toBe(true);
  });
});

describe('o que a troca propõe', () => {
  it('lista nominalmente o que mudaria', () => {
    const proposals = pendingProposals('marketing', {
      preChatFormEnabled: false,
      csatSurveyEnabled: true,
      continuityViaEmail: true,
      knowledgeBase: true,
    });

    expect(proposals.map(p => p.id)).toEqual([
      'preChatFormEnabled',
      'triggersPreset',
      'continuityViaEmail',
      'csatSurveyEnabled',
      'knowledgeBase',
    ]);
    expect(proposals[0].value).toBe(true);
    expect(proposals[3].value).toBe(false);
  });

  it('não propõe o que já está do jeito proposto', () => {
    const proposals = pendingProposals('marketing', {
      preChatFormEnabled: true,
      csatSurveyEnabled: false,
    });

    expect(proposals.map(p => p.id)).not.toContain('preChatFormEnabled');
    expect(proposals.map(p => p.id)).not.toContain('csatSurveyEnabled');
    expect(
      keptValues('marketing', { preChatFormEnabled: true }).map(p => p.id)
    ).toEqual(['preChatFormEnabled']);
  });

  it('trocar de perfil NÃO apaga: a proposta é uma lista, não uma escrita', () => {
    // O composable não escreve nada — devolve o que mudaria. Quem grava é a
    // tela, e só o que o administrador marcar.
    const antes = { csatSurveyEnabled: false, preChatFormEnabled: true };
    const copia = { ...antes };

    pendingProposals('support', antes);

    expect(antes).toEqual(copia);
  });
});

/**
 * Bloco 3.07 — o aplicador.
 *
 * O diagnostico mediu que o evento `apply` nao tinha ouvinte: cada caixa que o
 * administrador marcava caia no chao. Estes testes cobram o outro lado do
 * conserto — que a proposta aceita saiba dizer ONDE ela se escreve, e na FORMA
 * que o servidor aceita.
 */
describe('profileWrites — o ouvinte que faltava no `apply`', () => {
  const propostaDe = (profile, id) =>
    PROFILE_PROPOSALS[profile].find(item => item.id === id);

  it('cada proposta escreve no campo do rascunho, com o valor proposto', () => {
    const escritas = profileWrites(
      [
        propostaDe('marketing', 'preChatFormEnabled'),
        propostaDe('marketing', 'continuityViaEmail'),
        propostaDe('marketing', 'csatSurveyEnabled'),
      ],
      {}
    );

    expect(escritas).toEqual([
      { key: 'preChatEnabled', value: true },
      { key: 'continuityViaEmail', value: false },
      { key: 'csatSurveyEnabled', value: false },
    ]);
  });

  it('o preset de gatilho vira ESTRUTURA — nunca a string do preset', () => {
    const [escrita] = profileWrites(
      [propostaDe('marketing', 'triggersPreset')],
      {}
    );

    expect(escrita.key).toBe('triggers');
    // A string `'teaser_8s_30pct'` num campo que o schema exige objeto derruba
    // o PATCH inteiro com 422 (`ensure_widget_config_objects`).
    expect(typeof escrita.value).toBe('object');
    expect(escrita.value.enabled).toBe(true);
    expect(escrita.value.triggers).toEqual(RECOMMENDED_TRIGGERS);
  });

  it('o preset preserva os irmãos do grupo — o objeto viaja inteiro no PATCH', () => {
    const [escrita] = profileWrites(
      [propostaDe('marketing', 'triggersPreset')],
      {
        triggers: {
          approach: 'discreet',
          degrade_on_return: false,
          enabled: false,
          triggers: [],
        },
      }
    );

    // `approach` e `degrade_on_return` sobrevivem: trocar o perfil nao pode
    // apagar a abordagem que o administrador ja tinha escolhido.
    expect(escrita.value.approach).toBe('discreet');
    expect(escrita.value.degrade_on_return).toBe(false);
    expect(escrita.value.enabled).toBe(true);
  });

  it('`none` desliga o teaser e esvazia a lista', () => {
    const [escrita] = profileWrites([propostaDe('support', 'triggersPreset')], {
      triggers: { enabled: true, triggers: RECOMMENDED_TRIGGERS },
    });

    expect(escrita.value.enabled).toBe(false);
    expect(escrita.value.triggers).toEqual([]);
  });

  it('a proposta DERIVADA não gera escrita: ela é consequência do perfil', () => {
    const derivada = propostaDe('marketing', 'knowledgeBase');

    expect(derivada.derived).toBe(true);
    expect(profileWrites([derivada], {})).toEqual([]);
  });

  it('proposta sem aplicador LANÇA — nunca cai no chão em silêncio', () => {
    // Forçando a condição ruim: é assim que uma proposta nova acrescentada sem
    // aplicador se pareceria. O defeito que este bloco consertou era ela ser
    // ignorada com a tela dizendo que a troca fora aplicada.
    expect(() =>
      profileWrites([{ id: 'inventada', value: true }], {})
    ).toThrowError(/sem aplicador: inventada/);
  });

  it('preset de gatilho desconhecido LANÇA em vez de gravar lixo', () => {
    expect(() =>
      profileWrites(
        [{ id: 'triggersPreset', field: 'triggers', value: 'teaser_3s' }],
        {}
      )
    ).toThrowError(/preset de gatilho desconhecido: teaser_3s/);
  });

  it('TODA proposta dos dois perfis tem aplicador ou é declarada derivada', () => {
    // A trava: sem ela, a proxima proposta acrescentada a `PROFILE_PROPOSALS`
    // volta a cair no chao sem nenhum teste vermelho.
    Object.values(PROFILE_PROPOSALS)
      .flat()
      .forEach(proposal => {
        expect(
          Boolean(proposal.field) || Boolean(proposal.derived),
          `proposta ${proposal.id} sem \`field\` e sem \`derived\``
        ).toBe(true);
        if (proposal.field === 'triggers') {
          expect(TRIGGER_PRESETS[proposal.value]).toBeTypeOf('object');
        }
      });
  });
});

describe('triggersPresetOf — o que está gravado, dito no idioma da proposta', () => {
  it('gatilho desligado e lista vazia é `none`', () => {
    expect(triggersPresetOf({ enabled: false, triggers: [] })).toBe('none');
    expect(triggersPresetOf({})).toBe('none');
  });

  it('o recomendado ligado é `teaser_8s_30pct`', () => {
    expect(
      triggersPresetOf({ enabled: true, triggers: RECOMMENDED_TRIGGERS })
    ).toBe('teaser_8s_30pct');
  });

  it('qualquer outra combinação é `custom` — e `custom` nunca casa com proposta', () => {
    const custom = {
      enabled: true,
      triggers: [{ id: 'exit_intent', desktop: { enabled: true } }],
    };

    expect(triggersPresetOf(custom)).toBe('custom');
    // quem mexeu nos gatilhos a mao merece ver a proposta e decidir
    expect(
      pendingProposals('marketing', { triggersPreset: 'custom' }).map(p => p.id)
    ).toContain('triggersPreset');
  });

  it('valores mexidos a mão não passam por recomendado', () => {
    const quase = {
      enabled: true,
      triggers: [
        { id: 'time_on_page', desktop: { enabled: true, value: 3 } },
        { id: 'scroll_depth', desktop: { enabled: true, value: 30 } },
      ],
    };

    expect(triggersPresetOf(quase)).toBe('custom');
  });
});

describe('currentValuesFromDraft — o diálogo compara com o GRAVADO', () => {
  it('lê o rascunho da tela, e não um dublê de formato inventado', () => {
    expect(
      currentValuesFromDraft({
        preChatEnabled: true,
        continuityViaEmail: false,
        csatSurveyEnabled: true,
        profile: 'support',
        triggers: { enabled: false, triggers: [] },
      })
    ).toEqual({
      preChatFormEnabled: true,
      triggersPreset: 'none',
      continuityViaEmail: false,
      csatSurveyEnabled: true,
      knowledgeBase: true,
    });
  });

  it('as chaves são EXATAMENTE os ids das propostas', () => {
    const ids = PROFILE_PROPOSALS.marketing.map(p => p.id).sort();

    expect(Object.keys(currentValuesFromDraft({})).sort()).toEqual(ids);
  });

  it('em marketing a base de conhecimento já está escondida', () => {
    expect(currentValuesFromDraft({ profile: 'marketing' }).knowledgeBase).toBe(
      false
    );
  });
});
