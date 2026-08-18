import {
  PROFILE_CONFIG_DEFAULTS,
  profileConfigFromChannel,
  resolveProfileConfig,
} from '../profileConfigHelper';

const CANONICAL_KEYS = [
  'showKnowledgeBase',
  'showConversationList',
  'teaserEnabled',
  'teaserDelayMs',
  'teaserScrollPercent',
  'captureFlow',
  'primaryExit',
  'csatOnResolve',
  'emailContinuity',
  'homeLayout',
  'aiLabelPersistent',
];

describe('profileConfigHelper', () => {
  describe('a lista canônica (22-plano-widget §B.3)', () => {
    it('tem exatamente as 11 chaves do contrato, nem uma a mais', () => {
      expect(Object.keys(PROFILE_CONFIG_DEFAULTS).sort()).toEqual(
        [...CANONICAL_KEYS].sort()
      );
      expect(Object.keys(PROFILE_CONFIG_DEFAULTS)).toHaveLength(11);
    });

    it('os defaults são o perfil support da §B.3, valor por valor', () => {
      expect(PROFILE_CONFIG_DEFAULTS).toEqual({
        showKnowledgeBase: true,
        showConversationList: true,
        teaserEnabled: false,
        teaserDelayMs: 8000,
        teaserScrollPercent: 30,
        captureFlow: 'form',
        primaryExit: 'none',
        csatOnResolve: true,
        emailContinuity: true,
        homeLayout: 'support',
        aiLabelPersistent: true,
      });
    });
  });

  describe('degradação — 3.04 ainda não entregou a chave', () => {
    it('sem argumento algum devolve os 11 defaults', () => {
      expect(resolveProfileConfig()).toEqual(PROFILE_CONFIG_DEFAULTS);
    });

    it('profileConfig undefined no channelConfig devolve os 11 defaults', () => {
      expect(profileConfigFromChannel({ widgetColor: '#2dc46f' })).toEqual(
        PROFILE_CONFIG_DEFAULTS
      );
    });

    it('channelConfig inteiro ausente devolve os 11 defaults', () => {
      expect(profileConfigFromChannel()).toEqual(PROFILE_CONFIG_DEFAULTS);
    });

    it('null e tipos escalares não derrubam a resolução', () => {
      expect(resolveProfileConfig(null)).toEqual(PROFILE_CONFIG_DEFAULTS);
      expect(resolveProfileConfig('marketing')).toEqual(
        PROFILE_CONFIG_DEFAULTS
      );
      expect(resolveProfileConfig(42)).toEqual(PROFILE_CONFIG_DEFAULTS);
    });
  });

  describe('o que o servidor manda vence o default', () => {
    it('o perfil marketing da §B.4 atravessa inteiro', () => {
      const resolved = resolveProfileConfig({
        showKnowledgeBase: false,
        showConversationList: false,
        teaserEnabled: true,
        teaserDelayMs: 8000,
        teaserScrollPercent: 30,
        captureFlow: 'conversational',
        primaryExit: 'whatsapp',
        csatOnResolve: false,
        emailContinuity: false,
        homeLayout: 'marketing',
        aiLabelPersistent: true,
      });

      expect(resolved.showKnowledgeBase).toBe(false);
      expect(resolved.showConversationList).toBe(false);
      expect(resolved.teaserEnabled).toBe(true);
      expect(resolved.captureFlow).toBe('conversational');
      expect(resolved.primaryExit).toBe('whatsapp');
      expect(resolved.homeLayout).toBe('marketing');
      expect(resolved.csatOnResolve).toBe(false);
      expect(resolved.emailContinuity).toBe(false);
    });

    it('flag parcial não apaga as outras dez', () => {
      const resolved = resolveProfileConfig({ showKnowledgeBase: false });

      expect(resolved.showKnowledgeBase).toBe(false);
      expect(resolved.homeLayout).toBe('support');
      expect(resolved.showConversationList).toBe(true);
      expect(resolved.teaserDelayMs).toBe(8000);
    });
  });

  describe('servidor fora do contrato não apaga a tela', () => {
    it('enum desconhecido cai no default declarado', () => {
      expect(resolveProfileConfig({ homeLayout: 'xpto' }).homeLayout).toBe(
        'support'
      );
      expect(resolveProfileConfig({ captureFlow: 'wizard' }).captureFlow).toBe(
        'form'
      );
      expect(
        resolveProfileConfig({ primaryExit: 'telegram' }).primaryExit
      ).toBe('none');
    });

    it('enum em pt-BR é recusado — a arbitragem A2 manda valor em inglês snake_case', () => {
      expect(
        resolveProfileConfig({ homeLayout: 'marketing ' }).homeLayout
      ).toBe('support');
      expect(
        resolveProfileConfig({ captureFlow: 'conversacional' }).captureFlow
      ).toBe('form');
    });

    it('booleano mandado como string não vira true por coerção', () => {
      expect(
        resolveProfileConfig({ showKnowledgeBase: 'false' }).showKnowledgeBase
      ).toBe(true);
      expect(
        resolveProfileConfig({ showKnowledgeBase: 0 }).showKnowledgeBase
      ).toBe(true);
    });

    it('scroll fora de 0–100 e delay negativo caem no default', () => {
      expect(
        resolveProfileConfig({ teaserScrollPercent: 130 }).teaserScrollPercent
      ).toBe(30);
      expect(
        resolveProfileConfig({ teaserScrollPercent: -1 }).teaserScrollPercent
      ).toBe(30);
      expect(resolveProfileConfig({ teaserDelayMs: -500 }).teaserDelayMs).toBe(
        8000
      );
    });

    it('inteiro em string válida é aceito e truncado', () => {
      expect(
        resolveProfileConfig({ teaserDelayMs: '3000' }).teaserDelayMs
      ).toBe(3000);
      expect(
        resolveProfileConfig({ teaserScrollPercent: 45.9 }).teaserScrollPercent
      ).toBe(45);
    });

    it('chave desconhecida é descartada, não repassada', () => {
      const resolved = resolveProfileConfig({
        showKnowledgeBase: false,
        widgetProfile: 'marketing',
        experimentoNovo: true,
      });

      expect(resolved).not.toHaveProperty('widgetProfile');
      expect(resolved).not.toHaveProperty('experimentoNovo');
      expect(Object.keys(resolved)).toHaveLength(11);
    });
  });
});
