import { config, flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import campaignsModule from 'dashboard/store/modules/campaigns';
import CampaignsAPI from 'dashboard/api/campaigns';
import TeaserComposer from '../TeaserComposer.vue';

/**
 * Bloco 4.05 — o compositor do teaser **com a loja de verdade**.
 *
 * Por que este arquivo existe ao lado de `TeaserComposer.spec.js`: aquele dubla
 * `useMapGetter`, entao a campanha aparece na tela sem que ninguem tenha ido
 * busca-la. O teste passava, e em producao a lista era `[]` em visita direta ou
 * F5 — a tela mostrava "esta caixa ainda nao tem campanha" com a campanha
 * existindo no banco. Getter dublado nao mede o caminho que quebra.
 *
 * Aqui o unico duble e a camada HTTP (`dashboard/api/campaigns`). Roda de
 * verdade: a acao `campaigns/get`, a mutation `SET_CAMPAIGNS`, o getter
 * `getLiveChatCampaigns` e a acao `campaigns/update`. Assim o teste falha se o
 * despacho sumir, se o nome da acao mudar (`commit`/`dispatch` de acao
 * inexistente no Vuex nao lanca — so escreve no console) ou se o payload perder
 * um dos campos por que o getter filtra.
 *
 * A FORMA DO PAYLOAD e a que o servidor produz de verdade, fixada contra o
 * serializador em `spec/requests/spx/campaigns_live_chat_contract_spec.rb`
 * (`app/views/api/v1/models/_campaign.json.jbuilder`). E subconjunto — o `inbox`
 * de verdade traz umas quarenta chaves — mas todo campo presente aqui tem o
 * nome, o tipo e o valor que o servidor manda. O `id` e o `display_id`, e e ele
 * que volta no PATCH.
 */
vi.mock('dashboard/api/campaigns', () => ({
  default: { get: vi.fn(), update: vi.fn(), create: vi.fn() },
}));

const CAMPANHA_DESTA_CAIXA = {
  id: 3,
  title: 'Convite da página de planos',
  message: 'Posso ajudar a escolher o plano?',
  campaign_type: 'ongoing',
  campaign_status: 'active',
  enabled: true,
  trigger_rules: { url: 'https://simplex.test/planos' },
  inbox: { id: 7, name: 'Site da Simplex', channel_type: 'Channel::WebWidget' },
};

const CAMPANHA_DE_OUTRA_CAIXA = {
  id: 4,
  title: 'De outra caixa',
  message: 'Oi',
  campaign_type: 'ongoing',
  campaign_status: 'active',
  enabled: true,
  trigger_rules: { url: 'https://outra.test' },
  inbox: { id: 99, name: 'Outro site', channel_type: 'Channel::WebWidget' },
};

/**
 * O disparo de WhatsApp da mesma conta. Vem na MESMA resposta — o endpoint nao
 * filtra por tipo — e e o controle de que o getter real esta rodando: quem tira
 * este registro da tela e o filtro do getter (`ongoing` + `Channel::WebWidget`),
 * nao o teste. Com o getter dublado ele nunca teria chegado ate aqui.
 */
const CAMPANHA_DE_DISPARO = {
  id: 5,
  title: 'Disparo de agosto',
  message: 'Oferta',
  campaign_type: 'one_off',
  campaign_status: 'active',
  enabled: true,
  trigger_rules: {},
  inbox: { id: 12, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
};

const RESPOSTA_DO_SERVIDOR = [
  CAMPANHA_DESTA_CAIXA,
  CAMPANHA_DE_OUTRA_CAIXA,
  CAMPANHA_DE_DISPARO,
];

const [i18n] = config.global.plugins;

let store;
const toasts = [];
const anotaToast = ({ message }) => toasts.push(message);

// `mockReset: true` no `vitest.config.ts` limpa a implementacao entre os testes:
// se o `mockResolvedValue` ficasse no escopo do arquivo, o segundo teste receberia
// `undefined` e a acao morreria no `response.data`.
beforeEach(() => {
  i18n.global.locale.value = 'pt_BR';
  CampaignsAPI.get.mockResolvedValue({ data: RESPOSTA_DO_SERVIDOR });
  CampaignsAPI.update.mockImplementation((id, atributos) =>
    Promise.resolve({ data: { ...CAMPANHA_DESTA_CAIXA, ...atributos, id } })
  );
  store = createStore({
    modules: {
      campaigns: {
        ...campaignsModule,
        // Estado proprio por teste: o modulo exporta um objeto literal, e sem
        // isto os `records` de um teste vazariam para o seguinte.
        state: {
          records: [],
          uiFlags: { isFetching: false, isCreating: false },
        },
      },
    },
  });
  emitter.on('newToastMessage', anotaToast);
});

afterEach(() => {
  emitter.off('newToastMessage', anotaToast);
  toasts.length = 0;
  i18n.global.locale.value = 'en';
});

const montar = (inboxId = 7) =>
  mount(TeaserComposer, {
    props: { inboxId },
    global: { plugins: [store] },
  });

describe('TeaserComposer com a loja real', () => {
  it('busca as campanhas ao montar — sem isso a tela nao tem o que editar', async () => {
    // O estado inicial e o de producao em visita direta ou F5: loja vazia.
    expect(store.getters['campaigns/getLiveChatCampaigns']).toEqual([]);

    const wrapper = montar(7);
    await flushPromises();

    expect(CampaignsAPI.get).toHaveBeenCalledTimes(1);
    expect(
      wrapper.find('[data-testid="teaser-title"] input').element.value
    ).toBe('Convite da página de planos');
    expect(
      wrapper.find('[data-testid="teaser-message"] textarea').element.value
    ).toBe('Posso ajudar a escolher o plano?');
    // O banner de "sem campanha" e o defeito que este bloco fecha: ele afirmava
    // uma coisa falsa e nao oferecia campo nenhum para editar.
    expect(wrapper.find('[data-testid="teaser-empty"]').exists()).toBe(false);
  });

  it('o getter real e quem escolhe: nem a caixa ao lado, nem o disparo', async () => {
    montar(7);
    await flushPromises();

    // `getLiveChatCampaigns` = `ongoing` + `Channel::WebWidget`. O disparo de
    // WhatsApp veio na resposta e tem de ficar de fora.
    expect(
      store.getters['campaigns/getLiveChatCampaigns'].map(c => c.id)
    ).toEqual([3, 4]);
    expect(store.getters['campaigns/getAllCampaigns']).toHaveLength(3);
  });

  it('editar e salvar faz PATCH na campanha vinculada — e nunca POST', async () => {
    const wrapper = montar(7);
    await flushPromises();

    await wrapper
      .find('[data-testid="teaser-message"] textarea')
      .setValue('Quer ajuda para comparar os planos?');
    await wrapper.find('[data-testid="teaser-save"]').trigger('click');
    await flushPromises();

    // `3` e o `display_id`, que e o que a rota do PATCH consome.
    expect(CampaignsAPI.update).toHaveBeenCalledWith(3, {
      title: 'Convite da página de planos',
      message: 'Quer ajuda para comparar os planos?',
    });
    // O aceite negativo do bloco: nao nasce uma campanha por gatilho.
    expect(CampaignsAPI.create).not.toHaveBeenCalled();
    expect(toasts).toContain('Mensagem do convite salva.');
    // A mutation real gravou: a loja e a tela ficam com o texto novo.
    expect(store.getters['campaigns/getLiveChatCampaigns'][0].message).toBe(
      'Quer ajuda para comparar os planos?'
    );
  });

  it('enquanto a busca esta no ar a tela nao afirma que nao ha campanha', async () => {
    // Promessa presa de proposito: e o unico jeito de olhar a tela com o GET
    // ainda no ar. `isFetching` esta ligado, e o banner nao pode estar la.
    let entrega;
    CampaignsAPI.get.mockReturnValue(
      new Promise(resolve => {
        entrega = resolve;
      })
    );

    const wrapper = montar(7);
    await flushPromises();

    expect(store.getters['campaigns/getUIFlags'].isFetching).toBe(true);
    expect(wrapper.find('[data-testid="teaser-empty"]').exists()).toBe(false);

    entrega({ data: RESPOSTA_DO_SERVIDOR });
    await flushPromises();

    // Chegou a campanha: nem banner, e agora com campo para editar.
    expect(wrapper.find('[data-testid="teaser-empty"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="teaser-title"] input').element.value
    ).toBe('Convite da página de planos');
  });

  it('caixa sem campanha: busca, nao acha, e ai sim explica — sem criar nada', async () => {
    const wrapper = montar(1234);
    await flushPromises();

    expect(CampaignsAPI.get).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="teaser-empty"]').text()).toContain(
      'ainda não tem campanha de chat ao vivo'
    );
    expect(wrapper.find('[data-testid="teaser-save"]').exists()).toBe(false);
    expect(CampaignsAPI.create).not.toHaveBeenCalled();
    expect(CampaignsAPI.update).not.toHaveBeenCalled();
  });

  it('nao repete a busca quando a loja ja tem as campanhas', async () => {
    montar(7);
    await flushPromises();
    expect(CampaignsAPI.get).toHaveBeenCalledTimes(1);

    // Uma segunda montagem contra a MESMA loja — remontar ao voltar para a aba,
    // ou outro consumidor da mesma lista na mesma tela, como a secao "modo
    // antigo" (4.22) — nao pode render um segundo GET do mesmo endpoint.
    montar(7);
    await flushPromises();
    expect(CampaignsAPI.get).toHaveBeenCalledTimes(1);
  });
});
