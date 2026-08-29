import { config, flushPromises, mount } from '@vue/test-utils';
import { h } from 'vue';
import { createStore } from 'vuex';
import campaigns from 'dashboard/store/modules/campaigns';
import LegacyCampaigns from '../LegacyCampaigns.vue';

/**
 * 4.22 — A SEÇÃO "MODO ANTIGO" APARECE NA TELA, sem ninguém ter visitado Campanhas.
 *
 * POR QUE ESTE ARQUIVO EXISTE, se `LegacyCampaigns.spec.js` já tem 10 exemplos
 *
 * Aqueles dez trocam `dashboard/composables/store` inteiro por um dublê que devolve
 * a lista de campanhas pronta. Eles medem a LÓGICA da seção — quem entra na lista,
 * qual aviso, o que o botão chama — supondo o store já povoado. E era exatamente
 * essa suposição que produção não cumpria: nada na rota da caixa de entrada
 * despachava `campaigns/get`, então em visita direta ou F5 a lista era `[]`, o
 * `v-if="legadas.length"` não abria e a seção INTEIRA não existia. Os dez exemplos
 * ficavam verdes assim mesmo — o dublê entregava o dado que ninguém buscava.
 *
 * Aqui não há dublê de getter. O store é o módulo Vuex de verdade (`actions`,
 * `getters` e `mutations` do arquivo de produção), e o único dublê é a camada HTTP,
 * com o payload que o servidor devolve de fato: `api/v1/models/_campaign.json.jbuilder`
 * grava `json.id resource.display_id` (não existe campo `display_id` na resposta), a
 * caixa vem ANINHADA em `inbox` com `channel_type`, e `campaign_type` é `"ongoing"`.
 * As duas últimas coisas importam porque `getLiveChatCampaigns` filtra por elas — um
 * dublê sem esses campos devolveria lista vazia e este arquivo mediria o próprio erro.
 */

/** O payload REAL do índice de campanhas, campo por campo. */
const campanhaDoIndice = (extras = {}) => ({
  id: 3,
  title: '🔥 Convite dos planos',
  description: null,
  account_id: 1,
  inbox: {
    id: 7,
    name: 'Site da Simplex',
    channel_type: 'Channel::WebWidget',
    avatar_url: '',
  },
  sender: {},
  message: 'Posso ajudar a escolher?',
  template_params: null,
  campaign_status: 'active',
  enabled: true,
  campaign_type: 'ongoing',
  trigger_rules: { url: 'https://simplex.com.br', time_on_page: 10 },
  trigger_only_during_business_hours: false,
  created_at: '2026-08-20T12:00:00.000Z',
  updated_at: '2026-08-20T12:00:00.000Z',
  ...extras,
});

const get = vi.fn();
const importToTrigger = vi.fn().mockResolvedValue({ data: {} });
vi.mock('dashboard/api/campaigns', () => ({
  default: {
    get: (...args) => get(...args),
    importToTrigger: (...args) => importToTrigger(...args),
  },
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

const novoStore = () =>
  createStore({ modules: { campaigns: { ...campaigns, namespaced: true } } });

const montar = (store, props = {}) =>
  mount(LegacyCampaigns, {
    props: { inboxId: 7, gatilhoAtivo: true, ...props },
    global: { plugins: [store] },
  });

const [i18n] = config.global.plugins;
beforeEach(() => {
  i18n.global.locale.value = 'pt_BR';
  get.mockResolvedValue({ data: [campanhaDoIndice()] });
});

afterEach(() => {
  i18n.global.locale.value = 'en';
  alertas.length = 0;
});

describe('4.22 — a seção "modo antigo" com o store de verdade', () => {
  it('não existe antes da resposta, e existe depois — quem a faz aparecer é a própria montagem', async () => {
    const store = novoStore();
    // O ponto de partida honesto: ninguém visitou Campanhas nesta sessão.
    expect(store.state.campaigns.records).toEqual([]);

    const tela = montar(store);

    // Antes da resposta chegar, a seção realmente não está lá — é este o estado
    // que produção mostrava PARA SEMPRE em visita direta.
    expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);

    await flushPromises();

    expect(get).toHaveBeenCalledTimes(1);
    expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(true);
    expect(tela.find('[data-testid="modo-antigo-aviso"]').exists()).toBe(true);
    expect(tela.find('[data-testid="importar-campanha"]').exists()).toBe(true);
    expect(tela.text()).toContain('🔥 Convite dos planos');
  });

  it('o botão importa pelo `id` do payload, que é o `display_id` que a rota resolve', async () => {
    const tela = montar(novoStore());
    await flushPromises();

    await tela.find('[data-testid="importar-campanha"]').trigger('click');
    await flushPromises();

    // 3 é o `id` do payload. Não há `display_id` na resposta para cair de volta.
    expect(importToTrigger).toHaveBeenCalledWith(3);
  });

  describe('controles: a asserção sabe ficar vermelha', () => {
    it('campanha de OUTRA caixa não faz a seção aparecer', async () => {
      get.mockResolvedValue({
        data: [
          campanhaDoIndice({
            inbox: { id: 99, channel_type: 'Channel::WebWidget' },
          }),
        ],
      });

      const tela = montar(novoStore());
      await flushPromises();

      expect(get).toHaveBeenCalledTimes(1);
      expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);
    });

    it('campanha de disparo (`one_off`) não é modo antigo de chat de site', async () => {
      get.mockResolvedValue({
        data: [campanhaDoIndice({ campaign_type: 'one_off' })],
      });

      const tela = montar(novoStore());
      await flushPromises();

      // A busca TEM de ter acontecido: sem esta linha o exemplo passaria também
      // num mundo onde ninguém carrega nada — "não apareceu" por ausência de
      // sujeito é verde que não mede.
      expect(get).toHaveBeenCalledTimes(1);
      expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);
    });

    it('resposta vazia deixa a tela sem a seção — e não quebra', async () => {
      get.mockResolvedValue({ data: [] });

      const tela = montar(novoStore());
      await flushPromises();

      expect(get).toHaveBeenCalledTimes(1);
      expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);
    });

    it('a action ENGOLE o erro da rede, então a seção some em silêncio — está medido, não suposto', async () => {
      get.mockRejectedValue(new Error('500'));

      const tela = montar(novoStore());
      await flushPromises();

      expect(get).toHaveBeenCalledTimes(1);
      expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);
      expect(alertas).toEqual([]);
    });
  });

  it('dois consumidores na mesma tela fazem UMA requisição só', async () => {
    // O compositor do teaser (4.05) e esta seção montam no mesmo tique e pedem a
    // mesma lista. A guarda é o `isFetching`, que a action liga antes do primeiro
    // `await` — logo, de forma síncrona no `dispatch`.
    const store = novoStore();
    const Dupla = {
      render: () => [
        h(LegacyCampaigns, { inboxId: 7, gatilhoAtivo: true }),
        h(LegacyCampaigns, { inboxId: 7, gatilhoAtivo: false }),
      ],
    };

    const tela = mount(Dupla, { global: { plugins: [store] } });
    await flushPromises();

    expect(get).toHaveBeenCalledTimes(1);
    expect(tela.findAll('[data-testid="modo-antigo"]').length).toBe(2);
  });
});
