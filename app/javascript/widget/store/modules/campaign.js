import { getCampaigns, triggerCampaign } from 'widget/api/campaign';
import campaignTimer from 'widget/helpers/campaignTimer';
import {
  formatCampaigns,
  filterCampaigns,
} from 'widget/helpers/campaignHelper';
import { getFromCache, setCache } from 'shared/helpers/cache';
import { campanhaLegadaSuprimida } from 'shared/helpers/abordagemProativa';
import { emitSdkEventOnce } from 'widget/helpers/sdkEventEmitter';
import { CHATWOOT_CAMPAIGN_SHOWN } from 'widget/constants/sdkEvents';

const CACHE_KEY_PREFIX = 'chatwoot_campaigns_';

const state = {
  records: [],
  uiFlags: {
    hasFetched: false,
    isError: false,
  },
  activeCampaign: {},
};

const resetCampaignTimers = (
  campaigns,
  currentURL,
  websiteToken,
  isInBusinessHours
) => {
  // ─── Bloco 4.22 · precedência ────────────────────────────────────────────────
  // Enquanto o motor novo estiver no ar para esta conta, a campanha legada NÃO
  // dispara sozinha. A supressão é do RELÓGIO, e só dele: a campanha continua
  // buscada, continua em `records`, continua listada e editável no painel — ela
  // apenas deixa de agendar o próprio disparo. Apagá-la do store apagaria também
  // o texto que o 4.05 mostra como mensagem do convite.
  //
  // `initTimers([])` e não um `return` seco: ele começa limpando os relógios já
  // armados. Um `return` deixaria vivo um relógio de uma navegação anterior, e o
  // visitante levaria a campanha uma URL depois — a falha mais difícil de ver,
  // porque só aparece em site de página única.
  if (campanhaLegadaSuprimida(window.chatwootWebChannel)) {
    campaignTimer.initTimers({ campaigns: [] }, websiteToken);
    return;
  }

  const formattedCampaigns = formatCampaigns({ campaigns });
  // Find all campaigns that matches the current URL
  const filteredCampaigns = filterCampaigns({
    campaigns: formattedCampaigns,
    currentURL,
    isInBusinessHours,
  });
  campaignTimer.initTimers({ campaigns: filteredCampaigns }, websiteToken);
};

export const getters = {
  getCampaigns: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
  getActiveCampaign: $state => $state.activeCampaign,
};

export const actions = {
  fetchCampaigns: async (
    { commit },
    { websiteToken, currentURL, isInBusinessHours }
  ) => {
    try {
      // Cache for 1 hour
      const CACHE_EXPIRY = 60 * 60 * 1000;
      const cachedData = getFromCache(
        `${CACHE_KEY_PREFIX}${websiteToken}`,
        CACHE_EXPIRY
      );
      if (cachedData) {
        commit('setCampaigns', cachedData);
        commit('setError', false);
        resetCampaignTimers(
          cachedData,
          currentURL,
          websiteToken,
          isInBusinessHours
        );
        return;
      }

      const { data: campaigns } = await getCampaigns(websiteToken);
      setCache(`${CACHE_KEY_PREFIX}${websiteToken}`, campaigns);
      commit('setCampaigns', campaigns);
      commit('setError', false);
      resetCampaignTimers(
        campaigns,
        currentURL,
        websiteToken,
        isInBusinessHours
      );
    } catch (error) {
      commit('setError', true);
    }
  },
  initCampaigns: async (
    { getters: { getCampaigns: campaigns, getUIFlags: uiFlags }, dispatch },
    { currentURL, websiteToken, isInBusinessHours }
  ) => {
    if (!campaigns.length) {
      // This check is added to ensure that the campaigns are fetched once
      // On high traffic sites, if the campaigns are empty, the API is called
      // every time the user changes the URL (in case of the SPA)
      // So, we need to ensure that the campaigns are fetched only once
      if (!uiFlags.hasFetched) {
        dispatch('fetchCampaigns', {
          websiteToken,
          currentURL,
          isInBusinessHours,
        });
      }
    } else {
      resetCampaignTimers(
        campaigns,
        currentURL,
        websiteToken,
        isInBusinessHours
      );
    }
  },
  startCampaign: async (
    {
      commit,
      rootState: {
        appConfig: { isWidgetOpen },
      },
    },
    { websiteToken, campaignId }
  ) => {
    // Bloco 4.22 — segunda porta, e ela não é redundância inútil. `startCampaign`
    // é público na store e é o que um relógio remanescente chamaria; barrar aqui
    // é o que garante que "não dispara" valha mesmo se alguém agendar por outro
    // caminho no futuro.
    if (campanhaLegadaSuprimida(window.chatwootWebChannel)) return;

    // Disable campaign execution if widget is opened
    if (!isWidgetOpen) {
      const { data: campaigns } = await getCampaigns(websiteToken);
      // Check campaign is disabled or not
      const campaign = campaigns.find(item => item.id === campaignId);
      if (campaign) {
        commit('setActiveCampaign', campaign);
        // Bloco 5.04 — `chatwoot:campaign-shown`. Aqui, e não no componente do
        // teaser: o `resetCampaign` do fechamento do widget zera
        // `activeCampaign`, e um `mounted`/`watch` no componente re-emitiria a
        // cada abertura. O fato "esta campanha foi exibida" acontece uma vez
        // por campanha, e a chave do `once` é o id dela.
        emitSdkEventOnce(
          CHATWOOT_CAMPAIGN_SHOWN,
          { campaign_id: campaign.id },
          `${CHATWOOT_CAMPAIGN_SHOWN}:${campaign.id}`
        );
      }
    }
  },

  executeCampaign: async (
    { commit },
    { campaignId, websiteToken, customAttributes }
  ) => {
    try {
      commit(
        'conversation/setConversationUIFlag',
        { isCreating: true },
        { root: true }
      );
      await triggerCampaign({ campaignId, websiteToken, customAttributes });
      commit('setCampaignExecuted', true);
      commit('setActiveCampaign', {});
    } catch (error) {
      commit('setError', true);
    } finally {
      commit(
        'conversation/setConversationUIFlag',
        { isCreating: false },
        { root: true }
      );
    }
  },
  resetCampaign: async ({ commit }) => {
    try {
      commit('setCampaignExecuted', false);
      commit('setActiveCampaign', {});
    } catch (error) {
      commit('setError', true);
    }
  },
};

export const mutations = {
  setCampaigns($state, data) {
    $state.records = data;
    $state.uiFlags.hasFetched = true;
  },
  setActiveCampaign($state, data) {
    $state.activeCampaign = data;
  },
  setError($state, value) {
    $state.uiFlags.isError = value;
  },
  setHasFetched($state, value) {
    $state.uiFlags.hasFetched = value;
  },
  setCampaignExecuted($state, data) {
    $state.campaignHasExecuted = data;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
