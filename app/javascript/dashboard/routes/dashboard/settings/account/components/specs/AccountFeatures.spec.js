import { mount, flushPromises } from '@vue/test-utils';
import AccountFeatures from '../AccountFeatures.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ({ value: { installationName: 'Chat SPX' } }),
}));

const getSpy = vi.fn();
const updateSpy = vi.fn();
vi.mock('dashboard/api/accountFeatures', () => ({
  default: {
    get: (...args) => getSpy(...args),
    update: (...args) => updateSpy(...args),
  },
}));

const feature = (name, extra = {}) => ({
  name,
  display_name: name,
  enabled: false,
  premium: false,
  deprecated: false,
  internal: false,
  available: true,
  ...extra,
});

const catalogo = [
  feature('automations', { enabled: true }),
  feature('saml', { premium: true }),
  feature('recurso_indisponivel', { available: false }),
];

const montar = () =>
  mount(AccountFeatures, {
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        SectionLayout: { template: '<div><slot /></div>' },
        Spinner: true,
      },
    },
  });

describe('AccountFeatures', () => {
  beforeEach(() => {
    getSpy.mockReset().mockResolvedValue({ data: { features: catalogo } });
    updateSpy.mockReset().mockResolvedValue({ data: { features: catalogo } });
  });

  it('carrega o catalogo do backend, e nao de uma lista propria', async () => {
    montar();
    await flushPromises();

    expect(getSpy).toHaveBeenCalled();
  });

  it('exibe o nome da instalação em recursos com marca', async () => {
    getSpy.mockResolvedValue({
      data: {
        features: [feature('chatwoot_v4', { display_name: 'Chatwoot V4' })],
      },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain('Chat SPX V4');
    expect(wrapper.text()).not.toContain('Chatwoot');
    expect(wrapper.text()).not.toContain('chatwoot_v4');
  });

  it('mostra os tres grupos', async () => {
    const wrapper = montar();
    await flushPromises();

    // Texto real, e nao a chave: o `t` do useI18n resolve de verdade no ambiente de teste, entao
    // isto prova o que o usuario ve.
    const texto = wrapper.text();
    expect(texto).toContain('On');
    expect(texto).toContain('Available to turn on');
    expect(texto).toContain('Unavailable in this version');
  });

  it('avisa o motivo em quem nao cabe no bitmask', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain('the system feature limit was reached');
  });

  it('avisa que a premium e decisao comercial', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain('commercial decision');
  });

  it('grupo sem item nao aparece', async () => {
    getSpy.mockResolvedValue({
      data: { features: [feature('automations', { enabled: true })] },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).not.toContain('Unavailable in this version');
  });

  describe('ao alternar', () => {
    // MERGE: manda só a que mudou. Mandar o conjunto inteiro faria o backend apagar o resto.
    it('manda SO a feature que mudou', async () => {
      const wrapper = montar();
      await flushPromises();

      await wrapper.vm.alternar(feature('automations', { enabled: true }));

      expect(updateSpy).toHaveBeenCalledWith({ automations: false });
    });

    it('liga o que estava desligado', async () => {
      const wrapper = montar();
      await flushPromises();

      await wrapper.vm.alternar(feature('saml', { premium: true }));

      expect(updateSpy).toHaveBeenCalledWith({ saml: true });
    });

    it('NAO chama a API para quem esta indisponivel', async () => {
      const wrapper = montar();
      await flushPromises();

      await wrapper.vm.alternar(
        feature('recurso_indisponivel', { available: false })
      );

      expect(updateSpy).not.toHaveBeenCalled();
    });
  });
});
