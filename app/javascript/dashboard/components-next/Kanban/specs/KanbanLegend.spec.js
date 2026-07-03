import { shallowMount } from '@vue/test-utils';
import KanbanLegend from '../KanbanLegend.vue';
import { useKanbanGlossary } from '../composables/useKanbanGlossary';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const mountComponent = (props = {}) =>
  shallowMount(KanbanLegend, {
    props: { show: true, ...props },
    global: {
      stubs: { Icon: true, Button: true },
    },
  });

describe('KanbanLegend.vue', () => {
  const { groups, allTerms } = useKanbanGlossary();

  it('renders nothing when show is false', () => {
    const wrapper = mountComponent({ show: false });
    expect(wrapper.find('section').exists()).toBe(false);
  });

  it('renders a section for every glossary group', () => {
    const wrapper = mountComponent();
    expect(wrapper.findAll('section')).toHaveLength(groups.length);
  });

  it('renders a row for every term with its label and description', () => {
    const wrapper = mountComponent();
    expect(wrapper.findAll('li')).toHaveLength(allTerms.length);
    const text = wrapper.text();
    allTerms.forEach(term => {
      expect(text).toContain(term.labelKey);
      expect(text).toContain(term.descKey);
    });
  });

  it('emits close from the overlay button', async () => {
    const wrapper = mountComponent();
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
