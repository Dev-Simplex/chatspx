import { config, flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import LegacyCampaigns from '../LegacyCampaigns.vue';

/**
 * 4.22 — o MODO ANTIGO na tela.
 *
 * É rampa, não corte: a campanha continua listada e editável. O que esta seção
 * precisa fazer é dizer, sem rodeio, que ela não dispara enquanto o gatilho estiver
 * ligado — uma lista que só mostrasse "ativa" ao lado de algo que não dispara mais
 * seria pior que nenhuma seção.
 */
/**
 * O `id` aqui É o `display_id`, e não há campo `display_id` nenhum: é assim que o
 * serializador entrega (`api/v1/models/_campaign.json.jbuilder:1` grava
 * `json.id resource.display_id`). A fixture antiga trazia os dois campos com
 * valores diferentes — um formato que o servidor nunca produziu.
 */
const estado = reactive({
  campanhas: [
    {
      id: 3,
      title: '🔥 Convite dos planos',
      message: 'Posso ajudar a escolher?',
      enabled: true,
      campaign_type: 'ongoing',
      inbox: { id: 7, channel_type: 'Channel::WebWidget' },
    },
    {
      id: 4,
      title: 'Já importada',
      message: 'Oi',
      enabled: false,
      campaign_type: 'ongoing',
      inbox: { id: 7, channel_type: 'Channel::WebWidget' },
    },
    {
      id: 5,
      title: 'De outra caixa',
      message: 'Oi',
      enabled: true,
      campaign_type: 'ongoing',
      inbox: { id: 99, channel_type: 'Channel::WebWidget' },
    },
  ],
});

const dispatch = vi.fn().mockResolvedValue();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  // Chave a chave, com a forma real de cada getter: `getUIFlags` devolve o objeto
  // de flags, e não a lista. Um mock que devolvesse a mesma coisa para toda chave
  // faria a guarda de carregamento ler `isFetching` de dentro de um array.
  useMapGetter: chave => {
    if (chave === 'campaigns/getUIFlags')
      return { value: { isFetching: false } };
    return { value: estado.campanhas };
  },
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

const importToTrigger = vi.fn().mockResolvedValue({ data: {} });
vi.mock('dashboard/api/campaigns', () => ({
  default: { importToTrigger: (...args) => importToTrigger(...args) },
}));

const montar = (gatilhoAtivo = true) =>
  mount(LegacyCampaigns, { props: { inboxId: 7, gatilhoAtivo } });

// A suite roda em `en` por padrao; o que este bloco entrega e uma tela em pt-BR, e as
// asserções sao sobre o TEXTO — entao a locale e trocada de proposito. Isso tambem faz o
// arquivo falhar se alguem acrescentar a chave so em `en`, que e o defeito que uma
// asserção sobre a chave (e nao sobre o texto) deixaria passar.
const [i18n] = config.global.plugins;
beforeEach(() => {
  i18n.global.locale.value = 'pt_BR';
});

afterEach(() => {
  i18n.global.locale.value = 'en';
  alertas.length = 0;
  importToTrigger.mockClear();
  dispatch.mockClear();
});

describe('4.22 — a seção "modo antigo"', () => {
  it('lista só as campanhas LIGADAS desta caixa', () => {
    const tela = montar();
    const linhas = tela.findAll('[data-testid="importar-campanha"]');

    // A de outra caixa e a já importada (enabled false) ficam de fora.
    expect(linhas.length).toBe(1);
    expect(tela.text()).toContain('🔥 Convite dos planos');
    expect(tela.text()).not.toContain('De outra caixa');
    expect(tela.text()).not.toContain('Já importada');
  });

  it('some da tela quando não há campanha legada ligada', () => {
    const tela = mount(LegacyCampaigns, {
      props: { inboxId: 12345, gatilhoAtivo: true },
    });

    expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(false);
  });

  describe('o aviso, que é o produto desta seção', () => {
    it('diz que a campanha NÃO dispara quando o gatilho está ligado', () => {
      const aviso = montar(true).find('[data-testid="modo-antigo-aviso"]');

      expect(aviso.attributes('content')).toContain('não disparam sozinhas');
    });

    it('diz que ela continua disparando quando o gatilho está desligado', () => {
      const aviso = montar(false).find('[data-testid="modo-antigo-aviso"]');

      expect(aviso.attributes('content')).toContain('continuam disparando');
    });
  });

  describe('o botão de importar', () => {
    it('nasce com nome acessível que diz QUAL campanha — três "Importar" seriam três nomes iguais', () => {
      const botao = montar().find('[data-testid="importar-campanha"]');

      expect(botao.attributes('aria-label')).toBe(
        'Importar a campanha Convite dos planos como gatilho'
      );
    });

    it('tira o emoji do nome acessível e o mantém na tela', () => {
      const tela = montar();
      const botao = tela.find('[data-testid="importar-campanha"]');

      expect(botao.attributes('aria-label')).not.toContain('🔥');
      expect(tela.text()).toContain('🔥');
    });

    it('chama o endpoint com o display_id, que é o que a rota resolve', async () => {
      await montar().find('[data-testid="importar-campanha"]').trigger('click');
      await flushPromises();

      expect(importToTrigger).toHaveBeenCalledWith(3);
    });

    it('recarrega a lista depois de importar, para a campanha sair dela', async () => {
      const tela = montar();
      // A montagem já despacha `campaigns/get` (é o que faz a seção existir em
      // visita direta). Contar as chamadas é o que separa "recarregou depois de
      // importar" de "carregou ao montar" — sem isso a asserção passaria mesmo
      // se o import não recarregasse nada.
      expect(dispatch).toHaveBeenCalledTimes(1);

      await tela.find('[data-testid="importar-campanha"]').trigger('click');
      await flushPromises();

      expect(dispatch).toHaveBeenCalledTimes(2);
      expect(dispatch).toHaveBeenNthCalledWith(2, 'campaigns/get');
    });

    it('avisa em voz alta que a campanha foi desativada — as duas nunca ficam ligadas', async () => {
      await montar().find('[data-testid="importar-campanha"]').trigger('click');
      await flushPromises();

      expect(alertas[0]).toContain('desativada');
    });

    it('não some com a seção quando o import falha, e diz que falhou', async () => {
      importToTrigger.mockRejectedValueOnce(new Error('500'));
      const tela = montar();

      await tela.find('[data-testid="importar-campanha"]').trigger('click');
      await flushPromises();

      expect(alertas[0]).toContain('Não foi possível importar');
      expect(tela.find('[data-testid="modo-antigo"]').exists()).toBe(true);
    });
  });
});
