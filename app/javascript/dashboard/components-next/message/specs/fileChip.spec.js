import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import FileChip from '../chips/File.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));

const documentPayload = () => ({
  id: 10,
  message_id: 28,
  account_id: 1,
  file_type: 'file',
  file_size: 1258291,
  data_url: 'https://example.com/contrato-modelo-cliente.pdf',
  extension: 'pdf',
});

const render = attachment =>
  mount(FileChip, {
    props: { attachment },
    global: { directives: { tooltip: () => {} } },
  });

it.each(['raw', 'camelized'])(
  'shows the size separately from the truncated name for a %s API attachment without file_name',
  shape => {
    const payload = documentPayload();
    const attachment =
      shape === 'raw' ? payload : useCamelCase(payload, { deep: true });
    const wrapper = render(attachment);
    const size = wrapper.get('[data-testid="file-size"]');
    expect(size.text()).toBe('· 1,2 MB');
    expect(size.classes()).toContain('shrink-0');
    expect(size.classes()).toContain('whitespace-nowrap');
    const name = wrapper.get('span[title]');
    expect(name.text()).toBe('contrato-mod...pdf');
    expect(name.attributes('title')).toBe('contrato-modelo-cliente.pdf');
    expect(name.element.contains(size.element)).toBe(false);
    expect(wrapper.get('a').attributes('href')).toBe(payload.data_url);
  }
);

it('keeps the existing name and omits the separator when size is absent', () => {
  const attachment = useCamelCase(documentPayload(), { deep: true });
  delete attachment.fileSize;
  const wrapper = render(attachment);
  expect(wrapper.text()).toBe('contrato-mod...pdf');
  expect(wrapper.find('[data-testid="file-size"]').exists()).toBe(false);
});
