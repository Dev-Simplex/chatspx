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
 */
const estado = reactive({
  campanhas: [
    {
      id: 31,
      title: 'Convite da página de planos',
      message: 'Posso ajudar a escolher o plano?',
      inbox: { id: 7 },
    },
    { id: 32, title: 'De outra caixa', message: 'Oi', inbox: { id: 99 } },
  ],
  uiFlags: { isUpdating: false },
});

const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: chave =>
    chave === 'campaigns/getLiveChatCampaigns'
      ? { value: estado.campanhas }
      : { value: estado.uiFlags },
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
    expect(acoes).toEqual(['campaigns/update']);
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
    expect(dispatch).not.toHaveBeenCalled();
  });
});
