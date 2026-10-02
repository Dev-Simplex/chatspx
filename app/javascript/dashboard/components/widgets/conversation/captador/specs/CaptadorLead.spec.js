import { mount, flushPromises } from '@vue/test-utils';
import CaptadorLead from '../CaptadorLead.vue';
import CaptadorAPI from 'dashboard/api/integrations/captador';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/integrations/captador', () => ({
  default: { getLead: vi.fn(), moveStage: vi.fn() },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, vars) => (vars ? `${key} ${Object.values(vars).join(',')}` : key),
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const etapas = [
  { id: 1, nome: 'Novos', ordem: 1, ativa: true },
  { id: 2, nome: 'Qualificados', ordem: 2, ativa: true },
  { id: 3, nome: 'Proposta', ordem: 3, ativa: true },
  { id: 4, nome: 'Arquivada', ordem: 4, ativa: false },
];

const leadPayload = (overrides = {}) => ({
  lead: {
    id: 'lead-1',
    nome: 'Padaria X Ltda',
    cnpj: '12345678000199',
    origem: 'receita',
    etapa_id: 2,
    parado: true,
    dono: { id: 'u-1', nome: 'Maria' },
    ultima_atividade_em: new Date().toISOString(),
  },
  empresa: {
    situacao: { codigo: '02', descricao: 'Ativa' },
    cnae_principal: { codigo: '1091102', descricao: 'Padaria e confeitaria' },
    porte: { codigo: '01', descricao: 'Microempresa' },
    municipio: { nome: 'Cuiabá', uf: 'MT' },
    data_abertura: '2019-05-01',
    nao_contatar: false,
  },
  etapas,
  url: 'https://captador.test/funil/lead-1',
  ...overrides,
});

const render = (props = { conversationId: 99, leadId: 'lead-1' }) =>
  mount(CaptadorLead, {
    props,
    global: {
      stubs: { Icon: true, Spinner: true },
      directives: { onClickaway: {} },
    },
  });

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().includes(text));

// Abre o menu "Mover para…" e espera o DOM; o HTML vai na mensagem se o menu não abrir.
const openMoveMenu = async wrapper => {
  const moveButton = buttonWithText(wrapper, 'CAPTADOR.MOVE');
  await moveButton.trigger('click');
  await flushPromises();
  expect(moveButton.attributes('aria-expanded'), wrapper.html()).toBe('true');
};

describe('CaptadorLead', () => {
  afterEach(() => vi.clearAllMocks());

  it('não chama o Captador em conversa sem lead', async () => {
    const wrapper = render({ conversationId: 99, leadId: null });
    await flushPromises();

    expect(CaptadorAPI.getLead).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.CAPTADOR.EMPTY');
  });

  it('mostra o carregando e depois o lead com etapa, CNPJ e dados da Receita', async () => {
    CaptadorAPI.getLead.mockResolvedValue({ data: leadPayload() });
    const wrapper = render();

    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await flushPromises();

    expect(CaptadorAPI.getLead).toHaveBeenCalledWith(99);
    const text = wrapper.text();
    expect(text).toContain('Padaria X Ltda');
    expect(text).toContain('12.345.678/0001-99');
    expect(text).toContain('Qualificados');
    expect(text).toContain('CONVERSATION_SIDEBAR.CAPTADOR.STALLED');
    expect(text).toContain('Maria');
    expect(text).toContain('CONVERSATION_SIDEBAR.CAPTADOR.ORIGIN.RECEITA');
    expect(text).toContain('Ativa');
    expect(text).toContain('Padaria e confeitaria');
    expect(text).toContain('Cuiabá/MT');
    expect(text).toContain('01/05/2019');
    expect(wrapper.find('a').attributes('href')).toBe(
      'https://captador.test/funil/lead-1'
    );
    expect(wrapper.find('a').attributes('rel')).toContain('noopener');
  });

  it('trata lead não encontrado como conversa sem lead', async () => {
    CaptadorAPI.getLead.mockRejectedValue({ response: { status: 404 } });
    const wrapper = render();
    await flushPromises();

    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.CAPTADOR.EMPTY');
  });

  it('pede acesso quando o Captador responde acesso_pendente', async () => {
    CaptadorAPI.getLead.mockRejectedValue({
      response: { status: 403, data: { codigo: 'acesso_pendente' } },
    });
    const wrapper = render();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.CAPTADOR.PENDING_ACCESS'
    );
    expect(buttonWithText(wrapper, 'RETRY')).toBeUndefined();
  });

  it('avisa quando o Captador está fora e deixa tentar de novo', async () => {
    CaptadorAPI.getLead.mockRejectedValueOnce({
      response: { status: 502, data: { error_code: 'captador_unavailable' } },
    });
    CaptadorAPI.getLead.mockResolvedValueOnce({ data: leadPayload() });
    const wrapper = render();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.CAPTADOR.UNAVAILABLE'
    );
    await buttonWithText(wrapper, 'RETRY').trigger('click');
    await flushPromises();

    expect(CaptadorAPI.getLead).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('Padaria X Ltda');
  });

  it('move a etapa pelo menu, só com etapas ativas e diferentes da atual', async () => {
    CaptadorAPI.getLead.mockResolvedValue({ data: leadPayload() });
    CaptadorAPI.moveStage.mockResolvedValue({
      data: leadPayload({
        lead: { ...leadPayload().lead, etapa_id: 3, parado: false },
      }),
    });
    const wrapper = render();
    await flushPromises();

    await openMoveMenu(wrapper);
    expect(buttonWithText(wrapper, 'Novos')).toBeDefined();
    expect(buttonWithText(wrapper, 'Arquivada')).toBeUndefined();
    expect(buttonWithText(wrapper, 'Qualificados')).toBeUndefined();

    await buttonWithText(wrapper, 'Proposta').trigger('click');
    await flushPromises();

    expect(CaptadorAPI.moveStage).toHaveBeenCalledWith(99, 3);
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION_SIDEBAR.CAPTADOR.MOVED Proposta'
    );
    expect(wrapper.text()).not.toContain(
      'CONVERSATION_SIDEBAR.CAPTADOR.STALLED'
    );
  });

  it('avisa o erro ao mover e mantém a etapa', async () => {
    CaptadorAPI.getLead.mockResolvedValue({ data: leadPayload() });
    CaptadorAPI.moveStage.mockRejectedValue({ response: { status: 422 } });
    const wrapper = render();
    await flushPromises();

    await openMoveMenu(wrapper);
    await buttonWithText(wrapper, 'Proposta').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSATION_SIDEBAR.CAPTADOR.MOVE_ERROR'
    );
    expect(wrapper.text()).toContain('Qualificados');
  });

  it('esconde "Mover para…" quando o Captador diz que a pessoa não pode mover', async () => {
    CaptadorAPI.getLead.mockResolvedValue({
      data: leadPayload({ pode_mover: false }),
    });
    const wrapper = render();
    await flushPromises();

    expect(buttonWithText(wrapper, 'CAPTADOR.MOVE')).toBeUndefined();
    expect(wrapper.find('a').exists()).toBe(true);
  });
});
