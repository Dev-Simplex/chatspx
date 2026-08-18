/**
 * Bloco 3.05 — a ponta CONSUMIDORA das flags planas, vista pelo store.
 * O store e o `configMixin` LEEM O MESMO resolvedor; este spec prova que as duas
 * pontas concordam em valor, não só em existir.
 */
import { actions, getters, mutations } from '../../appConfig';
import { PROFILE_CONFIG_DEFAULTS } from 'widget/helpers/profileConfigHelper';
import { SET_PROFILE_CONFIG } from '../../../types';

const freshState = () => ({ profileConfig: { ...PROFILE_CONFIG_DEFAULTS } });

describe('appConfig — profileConfig (3.05)', () => {
  describe('estado inicial', () => {
    it('nasce nos 11 defaults do perfil support (A4)', () => {
      expect(getters.getProfileConfig(freshState())).toEqual(
        PROFILE_CONFIG_DEFAULTS
      );
      expect(getters.getHomeLayout(freshState())).toBe('support');
      expect(getters.getShowKnowledgeBase(freshState())).toBe(true);
      expect(getters.isMarketingHome(freshState())).toBe(false);
    });
  });

  describe('setAppConfig hidrata as flags', () => {
    afterEach(() => {
      delete window.chatwootWebChannel;
    });

    it('lê window.chatwootWebChannel quando o payload não traz a chave', () => {
      window.chatwootWebChannel = {
        profileConfig: { showKnowledgeBase: false, homeLayout: 'marketing' },
      };
      const commit = vi.fn();

      actions.setAppConfig({ commit }, { position: 'left' });

      expect(commit).toHaveBeenCalledWith(
        SET_PROFILE_CONFIG,
        expect.objectContaining({
          showKnowledgeBase: false,
          homeLayout: 'marketing',
          showConversationList: true,
        })
      );
    });

    it('sem window.chatwootWebChannel commita os defaults, não undefined', () => {
      const commit = vi.fn();

      actions.setAppConfig({ commit }, {});

      expect(commit).toHaveBeenCalledWith(
        SET_PROFILE_CONFIG,
        PROFILE_CONFIG_DEFAULTS
      );
    });

    it('profileConfig explícito no payload vence a janela', () => {
      window.chatwootWebChannel = {
        profileConfig: { homeLayout: 'support' },
      };
      const commit = vi.fn();

      actions.setAppConfig(
        { commit },
        { profileConfig: { homeLayout: 'marketing' } }
      );

      expect(commit).toHaveBeenCalledWith(
        SET_PROFILE_CONFIG,
        expect.objectContaining({ homeLayout: 'marketing' })
      );
    });
  });

  describe('mutação e getters derivados', () => {
    it('SET_PROFILE_CONFIG troca o objeto inteiro', () => {
      const state = freshState();
      const marketing = {
        ...PROFILE_CONFIG_DEFAULTS,
        showKnowledgeBase: false,
        homeLayout: 'marketing',
        primaryExit: 'whatsapp',
        captureFlow: 'conversational',
      };

      mutations[SET_PROFILE_CONFIG](state, marketing);

      expect(getters.getShowKnowledgeBase(state)).toBe(false);
      expect(getters.getHomeLayout(state)).toBe('marketing');
      expect(getters.isMarketingHome(state)).toBe(true);
      expect(getters.getPrimaryExit(state)).toBe('whatsapp');
      expect(getters.getCaptureFlow(state)).toBe('conversational');
      expect(getters.getTeaserDelayMs(state)).toBe(8000);
      expect(getters.getTeaserScrollPercent(state)).toBe(30);
    });
  });
});
