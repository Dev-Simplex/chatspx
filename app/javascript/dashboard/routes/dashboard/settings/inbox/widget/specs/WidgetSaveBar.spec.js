import { config, mount } from '@vue/test-utils';
import WidgetSaveBar from '../WidgetSaveBar.vue';

// O `vitest.setup.js` ja instala UMA instancia de i18n com todos os idiomas.
// Instalar outra por teste registra os componentes do vue-i18n duas vezes e
// enche a saida de warn — aqui basta trocar o idioma da instancia que existe.
const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};

afterEach(() => withLocale('en'));

const build = (props = {}, locale = 'pt_BR') => {
  withLocale(locale);
  return mount(WidgetSaveBar, {
    props: { dirtyCount: 0, isSaving: false, errorMessage: '', ...props },
  });
};

describe('WidgetSaveBar', () => {
  it('não aparece sem alteração pendente', () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
  });

  it('anuncia UMA alteração no singular', () => {
    const wrapper = build({ dirtyCount: 1 });
    expect(wrapper.find('[data-testid="pending-count"]').text()).toBe(
      '1 alteração não salva'
    );
  });

  it('anuncia N alterações não salvas', () => {
    const wrapper = build({ dirtyCount: 4 });
    expect(wrapper.find('[data-testid="pending-count"]').text()).toBe(
      '4 alterações não salvas'
    );
  });

  it('anuncia em en também', () => {
    const wrapper = build({ dirtyCount: 4 }, 'en');
    expect(wrapper.find('[data-testid="pending-count"]').text()).toBe(
      '4 unsaved changes'
    );
  });

  it('é uma região viva para leitor de tela', () => {
    const wrapper = build({ dirtyCount: 2 });
    const region = wrapper.find('[role="region"]');
    expect(region.attributes('aria-live')).toBe('polite');
    expect(region.attributes('aria-label')).toBe('Alterações não salvas');
  });

  it('Descartar e Salvar avisam quem consome', async () => {
    const wrapper = build({ dirtyCount: 2 });

    await wrapper.find('[data-testid="discard-button"]').trigger('click');
    await wrapper.find('[data-testid="save-button"]').trigger('click');

    expect(wrapper.emitted('discard')).toHaveLength(1);
    expect(wrapper.emitted('save')).toHaveLength(1);
  });

  it('erro de gravação continua na tela depois do toast sumir', () => {
    const wrapper = build({ dirtyCount: 0, errorMessage: 'position inválida' });
    expect(wrapper.find('[data-testid="save-error"]').text()).toBe(
      'position inválida'
    );
  });
});
