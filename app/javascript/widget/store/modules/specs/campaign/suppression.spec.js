import { actions } from '../../campaign';
import { campaigns } from './data';
import campaignTimer from 'widget/helpers/campaignTimer';

vi.mock('widget/helpers/campaignTimer', () => ({
  default: { initTimers: vi.fn() },
}));

// A API e dublada para que o vermelho do exemplo de `startCampaign` seja a
// ASSERCAO, e nao um 404 de rede: sem o dublê, tirar a guarda faz o teste falhar
// por a requisicao nao existir, o que provaria a ausencia do servidor e nao a
// ausencia da regra.
vi.mock('widget/api/campaign', () => ({
  getCampaigns: vi.fn(() =>
    Promise.resolve({ data: [{ id: 1, title: 'Welcome' }] })
  ),
  triggerCampaign: vi.fn(() => Promise.resolve({})),
}));

/**
 * 4.22 — a precedência COMO COMPORTAMENTO, e não só como predicado.
 *
 * O aceite que este arquivo carrega é o de NÃO REGRESSÃO: a conta que só tem
 * campanha legada não pode mudar de comportamento. É o teste que protege a frota
 * inteira, porque hoje ela é toda assim.
 */
describe('4.22 — precedência entre campanha legada e abordagem nova', () => {
  const websiteToken = 'token-do-site';
  const currentURL = 'https://github.com';

  const comCampanhasNaStore = {
    getters: { getCampaigns: campaigns, getUIFlags: { hasFetched: true } },
    dispatch: vi.fn(),
  };

  const initCampaigns = () =>
    actions.initCampaigns(comCampanhasNaStore, {
      currentURL,
      websiteToken,
      isInBusinessHours: true,
    });

  const canal = gatilhos => {
    window.chatwootWebChannel = gatilhos
      ? { widgetTriggers: gatilhos }
      : undefined;
  };

  beforeEach(() => {
    campaignTimer.initTimers.mockClear();
    comCampanhasNaStore.dispatch.mockClear();
  });

  afterEach(() => {
    delete window.chatwootWebChannel;
  });

  describe('a conta que SÓ tem campanha legada — a frota de hoje', () => {
    it('continua agendando a campanha, exatamente como antes', async () => {
      canal({});

      await initCampaigns();

      expect(campaignTimer.initTimers).toHaveBeenCalledTimes(1);
      const [{ campaigns: agendadas }, token] =
        campaignTimer.initTimers.mock.calls[0];
      expect(agendadas.length).toBe(1);
      expect(agendadas[0].id).toBe(1);
      expect(token).toBe(websiteToken);
    });

    it('continua agendando quando o canal nem existe', async () => {
      canal(null);

      await initCampaigns();

      const [{ campaigns: agendadas }] = campaignTimer.initTimers.mock.calls[0];
      expect(agendadas.length).toBe(1);
    });
  });

  describe('a conta com os DOIS ativos', () => {
    it('não agenda campanha nenhuma — o visitante vê uma mensagem só, a do gatilho', async () => {
      canal({ enabled: true });

      await initCampaigns();

      expect(campaignTimer.initTimers).toHaveBeenCalledTimes(1);
      const [{ campaigns: agendadas }] = campaignTimer.initTimers.mock.calls[0];
      expect(agendadas).toEqual([]);
    });

    it('LIMPA os relógios em vez de só não agendar — senão a campanha chega uma URL depois', async () => {
      canal({ enabled: true });

      await initCampaigns();

      // A chamada acontece: é ela que zera o que ficou de uma navegação anterior
      // num site de página única. Um `return` seco deixaria o relógio vivo.
      expect(campaignTimer.initTimers).toHaveBeenCalledTimes(1);
    });

    it('recusa o disparo mesmo se alguém chamar startCampaign direto', async () => {
      canal({ enabled: true });
      const commit = vi.fn();

      await actions.startCampaign(
        { commit, rootState: { appConfig: { isWidgetOpen: false } } },
        { websiteToken, campaignId: 1 }
      );

      expect(commit).not.toHaveBeenCalled();
    });

    it('e o mesmo startCampaign ATIVA a campanha quando não há gatilho — a guarda é da regra, não um "nunca"', async () => {
      canal({});
      const commit = vi.fn();

      await actions.startCampaign(
        { commit, rootState: { appConfig: { isWidgetOpen: false } } },
        { websiteToken, campaignId: 1 }
      );

      expect(commit).toHaveBeenCalledWith('setActiveCampaign', {
        id: 1,
        title: 'Welcome',
      });
    });
  });

  describe('desligando o gatilho', () => {
    it('a campanha legada volta a ser agendada, sem republicar nada', async () => {
      canal({ enabled: true });
      await initCampaigns();
      const [{ campaigns: sobSupressao }] =
        campaignTimer.initTimers.mock.calls[0];
      expect(sobSupressao).toEqual([]);

      // O administrador desliga o gatilho: o payload de boot muda, e nada mais.
      // Nenhuma campanha foi editada, desativada ou republicada no meio.
      campaignTimer.initTimers.mockClear();
      canal({ enabled: false });
      await initCampaigns();

      const [{ campaigns: depois }] = campaignTimer.initTimers.mock.calls[0];
      expect(depois.length).toBe(1);
      expect(depois[0].id).toBe(1);
    });
  });
});
