import { ref } from 'vue';
import {
  DEFAULT_PROFILE,
  hiddenSectionsFor,
  keptValues,
  normalizeProfile,
  otherProfile,
  pendingProposals,
  useProfileVisibility,
} from '../useProfileVisibility';

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
