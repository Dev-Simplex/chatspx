import { config, mount } from '@vue/test-utils';
import BrandColorField from '../BrandColorField.vue';

const [i18n] = config.global.plugins;
i18n.global.locale.value = 'pt_BR';
afterEach(() => {
  i18n.global.locale.value = 'en';
});

const build = (modelValue = '#2dc46f') => {
  i18n.global.locale.value = 'pt_BR';
  return mount(BrandColorField, {
    props: { modelValue },
    global: { stubs: { ColorPicker: true } },
  });
};

describe('BrandColorField', () => {
  it('digitar no campo hex avisa quem consome, sem tocar no store', async () => {
    const wrapper = build();

    await wrapper.find('input').setValue('#009ce0');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['#009ce0']);
  });

  it('valor inválido reclama no campo mas NÃO bloqueia nem some com o medidor', () => {
    const wrapper = build('#zz');

    expect(wrapper.text()).toContain('Use o formato #RRGGBB.');
    expect(wrapper.find('[data-testid="contrast-readout"]').exists()).toBe(
      true
    );
    expect(wrapper.find('input').attributes('disabled')).toBeUndefined();
  });

  it('valor válido mostra o medidor com a leitura da cor', () => {
    const wrapper = build('#2dc46f');

    expect(
      wrapper.find('[data-testid="contrast-brandAsTextLight"]').text()
    ).toContain('2,27:1');
  });
});
