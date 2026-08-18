/**
 * Bloco 3.05 — a ponta CONSUMIDORA das flags planas, vista pelo mixin.
 * Contrato: 22-plano-widget §B.3 (lista canônica).
 */
import { shallowMount } from '@vue/test-utils';
import { reactive } from 'vue';
import configMixin from '../configMixin';

const mountWith = channelConfig =>
  shallowMount({
    mixins: [configMixin],
    data() {
      return { channelConfig: reactive(channelConfig) };
    },
    template: '<div />',
  });

const BASE_CHANNEL = {
  avatarUrl: 'https://test.url',
  enabledFeatures: [],
  preChatFormOptions: { pre_chat_fields: [], pre_chat_message: '' },
  preChatFormEnabled: false,
};

describe('configMixin — flags planas do perfil (3.05)', () => {
  describe('3.04 ainda não entregou a chave', () => {
    it('sem profileConfig o mixin devolve o perfil support inteiro', () => {
      const vm = mountWith({ ...BASE_CHANNEL }).vm;

      expect(vm.profileConfig).toEqual({
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

    it('e o comportamento de hoje continua: base de conhecimento visível, home support', () => {
      const vm = mountWith({ ...BASE_CHANNEL }).vm;

      expect(vm.showKnowledgeBase).toBe(true);
      expect(vm.isSupportHome).toBe(true);
      expect(vm.isMarketingHome).toBe(false);
      expect(vm.showConversationList).toBe(true);
      expect(vm.isTeaserEnabled).toBe(false);
      expect(vm.hasWhatsAppExit).toBe(false);
      expect(vm.isConversationalCapture).toBe(false);
    });
  });

  describe('perfil marketing entregue pelo servidor', () => {
    const marketing = {
      ...BASE_CHANNEL,
      profileConfig: {
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
      },
    };

    it('cada flag nomeada reflete o valor do servidor', () => {
      const vm = mountWith(marketing).vm;

      expect(vm.showKnowledgeBase).toBe(false);
      expect(vm.showConversationList).toBe(false);
      expect(vm.isMarketingHome).toBe(true);
      expect(vm.isSupportHome).toBe(false);
      expect(vm.isConversationalCapture).toBe(true);
      expect(vm.hasWhatsAppExit).toBe(true);
      expect(vm.isTeaserEnabled).toBe(true);
      expect(vm.hasCsatOnResolve).toBe(false);
      expect(vm.hasEmailContinuity).toBe(false);
      expect(vm.isAiLabelPersistent).toBe(true);
    });
  });

  it('o mixin NÃO expõe o nome do perfil — regra A3', () => {
    const vm = mountWith({
      ...BASE_CHANNEL,
      widgetProfile: 'marketing',
      profileConfig: { homeLayout: 'marketing' },
    }).vm;

    expect(vm.profileConfig).not.toHaveProperty('widgetProfile');
    expect(vm.isMarketingHome).toBe(true);
  });
});
