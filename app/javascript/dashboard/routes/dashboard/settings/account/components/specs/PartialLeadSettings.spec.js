import { mount, flushPromises } from '@vue/test-utils';
import PartialLeadSettings from '../PartialLeadSettings.vue';

/**
 * Bloco 4.18 — a tela das quatro decisões do lead incompleto.
 *
 * O que este arquivo mede é a ponte, não a aparência: a tela desenha o que o SERVIDOR
 * devolveu (nunca um padrão próprio) e devolve ao servidor o que o administrador mexeu.
 * As duas metades importam porque o defeito que o bloco corrige é "a configuração existe e
 * ninguém alcança".
 */
const { alertSpy, apiGet, apiSet } = vi.hoisted(() => ({
  alertSpy: vi.fn(),
  apiGet: vi.fn(),
  apiSet: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({ useAlert: alertSpy }));

vi.mock('dashboard/api/partialLeadSettings', () => ({
  default: { get: apiGet, set: apiSet },
}));

// O corpo REAL do endpoint (`Widget::PartialLeads::Settings#to_h`): quatro chaves, valores
// já resolvidos. Dublê com forma diferente da do servidor mede a si mesmo.
const RESPOSTA_DO_SERVIDOR = {
  partial_lead_capture_enabled: false,
  partial_lead_abandon_after_minutes: 5,
  partial_lead_retention_days: 30,
  partial_lead_label: 'lead-incompleto',
};

const montar = async (data = RESPOSTA_DO_SERVIDOR) => {
  apiGet.mockResolvedValue({ data });
  const wrapper = mount(PartialLeadSettings);
  await flushPromises();
  return wrapper;
};

const campo = (wrapper, testid) =>
  wrapper.find(`[data-testid="${testid}"] input`);

describe('PartialLeadSettings (4.18)', () => {
  it('desenha os valores que o SERVIDOR resolveu, sem padrão próprio', async () => {
    // A tela não escreve "5" nem "30" em lugar nenhum: se escrevesse, um dia o servidor
    // mudaria o padrão e a tela continuaria mostrando o antigo — com a suíte verde.
    const wrapper = await montar({
      ...RESPOSTA_DO_SERVIDOR,
      partial_lead_abandon_after_minutes: 15,
      partial_lead_retention_days: 7,
      partial_lead_label: 'perdido',
    });

    expect(campo(wrapper, 'partial-lead-abandon').element.value).toBe('15');
    expect(campo(wrapper, 'partial-lead-retention').element.value).toBe('7');
    expect(campo(wrapper, 'partial-lead-label').element.value).toBe('perdido');
  });

  it('ligar a captura manda a chave que o servidor lê', async () => {
    const wrapper = await montar();
    apiSet.mockResolvedValue({
      data: { ...RESPOSTA_DO_SERVIDOR, partial_lead_capture_enabled: true },
    });

    await wrapper.find('[data-testid="partial-lead-enabled"]').trigger('click');
    await flushPromises();

    expect(apiSet).toHaveBeenCalledWith({ partial_lead_capture_enabled: true });
  });

  it('a retenção vai ao servidor como NÚMERO, e só quando o campo é confirmado', async () => {
    const wrapper = await montar();
    apiSet.mockResolvedValue({
      data: { ...RESPOSTA_DO_SERVIDOR, partial_lead_retention_days: 7 },
    });

    const input = campo(wrapper, 'partial-lead-retention');
    await input.setValue('7');
    // Sem o blur nada sai: salvar a cada tecla gravaria "7" no caminho de "70".
    expect(apiSet).not.toHaveBeenCalled();

    await input.trigger('blur');
    await flushPromises();

    expect(apiSet).toHaveBeenCalledWith({ partial_lead_retention_days: 7 });
  });

  it('adota o valor NORMALIZADO que voltou, em vez do que foi digitado', async () => {
    // É a metade que impede a tela de mentir: "para sempre" volta como 30 e o campo tem de
    // mostrar 30. Sem isso o administrador fecha a tela acreditando numa retenção que o
    // servidor ignora.
    const wrapper = await montar();
    apiSet.mockResolvedValue({
      data: { ...RESPOSTA_DO_SERVIDOR, partial_lead_retention_days: 30 },
    });

    const input = campo(wrapper, 'partial-lead-retention');
    await input.setValue('para sempre');
    await input.trigger('blur');
    await flushPromises();

    expect(campo(wrapper, 'partial-lead-retention').element.value).toBe('30');
  });

  it('a etiqueta viaja como texto, e vazia continua vazia', async () => {
    const wrapper = await montar();
    apiSet.mockResolvedValue({
      data: { ...RESPOSTA_DO_SERVIDOR, partial_lead_label: '' },
    });

    const input = campo(wrapper, 'partial-lead-label');
    await input.setValue('');
    await input.trigger('blur');
    await flushPromises();

    expect(apiSet).toHaveBeenCalledWith({ partial_lead_label: '' });
    expect(campo(wrapper, 'partial-lead-label').element.value).toBe('');
  });

  it('o aviso de retenção só aparece com a captura LIGADA', async () => {
    const desligada = await montar();
    expect(desligada.find('[data-testid="partial-lead-lgpd"]').exists()).toBe(
      false
    );

    const ligada = await montar({
      ...RESPOSTA_DO_SERVIDOR,
      partial_lead_capture_enabled: true,
    });
    // Par positivo: sem ele, "não aparece" passaria também numa tela que nunca mostra o aviso.
    expect(ligada.find('[data-testid="partial-lead-lgpd"]').text()).toContain(
      '30'
    );
  });

  it('endpoint fora do ar mostra erro em vez de campos com valores inventados', async () => {
    apiGet.mockRejectedValue(new Error('500'));
    const wrapper = mount(PartialLeadSettings);
    await flushPromises();

    expect(wrapper.find('[data-testid="partial-lead-error"]').exists()).toBe(
      true
    );
    expect(campo(wrapper, 'partial-lead-retention').exists()).toBe(false);
  });
});
