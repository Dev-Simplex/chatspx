import { shallowMount } from '@vue/test-utils';
import ContactSelector from '../ContactSelector.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => `${key}${params ? ` ${params.id}` : ''}`,
  }),
}));

// S-03: com so o nome, a busca devolvia "Juliana", "Juliana", "Juliana".
const menuItemsFor = contacts =>
  shallowMount(ContactSelector, {
    props: {
      contacts,
      showContactsDropdown: true,
      isLoading: false,
      isCreatingContact: false,
      showInboxesDropdown: false,
    },
  })
    .findComponent({ name: 'TagInput' })
    .props('menuItems');

describe('ContactSelector', () => {
  it('shows the phone and last activity under the name', () => {
    const [item] = menuItemsFor([
      {
        id: 1,
        name: 'Juliana',
        phoneNumber: '+5565992476302',
        lastActivityAt: Math.floor(Date.now() / 1000) - 2 * 86400,
      },
    ]);

    expect(item.label).toBe('Juliana');
    expect(item.description).toContain('+55 65 99247 6302');
    expect(item.description).toContain('há 2 dias');
    expect(item.badge).toBeNull();
  });

  it('keeps the email for a contact without phone', () => {
    const [item] = menuItemsFor([
      { id: 2, name: 'Juliana', email: 'juliana@exemplo.com' },
    ]);

    expect(item.description).toBe('juliana@exemplo.com');
  });

  it('flags a duplicate contact with the id of the other one', () => {
    const [item] = menuItemsFor([
      { id: 3, name: 'Juliana', phoneNumber: '+5565992476302', duplicateOf: 4 },
    ]);

    expect(item.badge).toBe(
      'COMPOSE_NEW_CONVERSATION.FORM.CONTACT_SELECTOR.DUPLICATE_BADGE 4'
    );
  });
});
