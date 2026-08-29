import { config, flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import TeaserComposer from '../TeaserComposer.vue';

/**
 * Bloco 4.05: **campanha e mensagem, gatilho e momento**.
 *
 * Os dois aceites do bloco sao negativos e positivos ao mesmo tempo: editar o
 * texto do teaser edita a campanha VINCULADA, e nao nasce uma campanha por
 * gatilho. O segundo e o que impede o produto de ganhar duas listas
 * concorrentes de mensagem proativa.
 *
 * ESTE ARQUIVO MEDE SO A RENDERIZACAO. Ele dubla `useMapGetter`, entao a
 * campanha aparece na tela sem que ninguem tenha ido busca-la — e foi por isso
 * que ele ficou verde com a tela quebrada em producao, onde a lista chegava `[]`
 * em visita direta ou F5. Quem prova o caminho inteiro, com loja e getter de
 * verdade e so a camada HTTP dublada, e `TeaserComposer.storeReal.spec.js`.
 * As duas afirmacoes sobre despacho aqui embaixo existem para que este arquivo
 * pelo menos nao volte a afirmar o contrario do que a tela faz.
 */
const estado = reactive({
  // A forma e a do serializador de verdade (`_campaign.json.jbuilder`), fixada em
  // `spec/requests/spx/campaigns_live_chat_contract_spec.rb`. Com o getter dublado
  // ela nao muda o resultado deste arquivo — esta aqui para nao deixar na pasta um
  // fixture com um formato que o backend nunca produziu.
  campanhas: [
    {
      id: 31,
      title: 'Convite da página de planos',
      message: 'Posso ajudar a escolher o plano?',
      campaign_type: 'ongoing',
      enabled: true,
      inbox: { id: 7, channel_type: 'Channel::WebWidget' },
    },
    {
      id: 32,
      title: 'De outra caixa',
      message: 'Oi',
      campaign_type: 'ongoing',
      enabled: true,
      inbox: { id: 99, channel_type: 'Channel::WebWidget' },
    },
  ],
  uiFlags: { isUpdating: false },
});

const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: chave => {
    if (chave === 'campaigns/getLiveChatCampaigns') {
      return { value: estado.campanhas };
    }
    // `getAllCampaigns` decide a guarda do `campaigns/get` na montagem. Vazio
    // aqui de proposito: e o estado de producao em visita direta, o unico em que
    // a tela precisa buscar.
    if (chave === 'campaigns/getAllCampaigns') return { value: [] };
    return { value: estado.uiFlags };
  },
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

const [i18n] = config.global.plugins;
afterEach(() => {
  i18n.global.locale.value = 'en';
  alertas.length = 0;
});

const build = (inboxId = 7) => {
  i18n.global.locale.value = 'pt_BR';
  return mount(TeaserComposer, { props: { inboxId } });
};

describe('TeaserComposer', () => {
  it('mostra a campanha DESTA caixa, não a da caixa ao lado', () => {
    const wrapper = build(7);

    expect(
      wrapper.find('[data-testid="teaser-title"] input').element.value
    ).toBe('Convite da página de planos');
    expect(wrapper.find('[data-testid="teaser-link"]').text()).toContain(
      'Convite da página de planos'
    );
  });

  it('editar o texto e salvar EDITA a campanha vinculada', async () => {
    const wrapper = build(7);

    await wrapper
      .find('[data-testid="teaser-message"] textarea')
      .setValue('Quer ajuda para comparar os planos?');
    await wrapper.find('[data-testid="teaser-save"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('campaigns/update', {
      id: 31,
      title: 'Convite da página de planos',
      message: 'Quer ajuda para comparar os planos?',
    });
    expect(alertas).toContain('Mensagem do convite salva.');
  });

  it('NÃO cria campanha: o único despacho possível é `update`', async () => {
    const wrapper = build(7);

    await wrapper.find('[data-testid="teaser-title"] input').setValue('Outro');
    await wrapper.find('[data-testid="teaser-save"]').trigger('click');
    await flushPromises();

    const acoes = dispatch.mock.calls.map(([acao]) => acao);
    // Buscar e salvar, nessa ordem, e nada mais: `campaigns/create` nunca entra.
    expect(acoes).toEqual(['campaigns/get', 'campaigns/update']);
    expect(acoes).not.toContain('campaigns/create');
  });

  it('sem edição, o botão de salvar fica desabilitado', () => {
    const wrapper = build(7);

    expect(
      wrapper.find('[data-testid="teaser-save"]').attributes('disabled')
    ).toBeDefined();
  });

  it('caixa sem campanha explica onde criar — e não cria sozinha', () => {
    const wrapper = build(1234);

    expect(wrapper.find('[data-testid="teaser-empty"]').text()).toContain(
      'ainda não tem campanha de chat ao vivo'
    );
    expect(wrapper.find('[data-testid="teaser-save"]').exists()).toBe(false);
    // A tela BUSCA e so entao conclui que nao ha campanha. O banner so pode
    // aparecer depois da busca: antes dela ele afirmaria uma coisa que a tela
    // ainda nao sabe — que era exatamente o defeito deste bloco.
    expect(dispatch.mock.calls.map(([acao]) => acao)).toEqual([
      'campaigns/get',
    ]);
  });
});
