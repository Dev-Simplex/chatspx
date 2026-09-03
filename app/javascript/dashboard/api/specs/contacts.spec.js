import contactAPI, { buildContactParams } from '../contacts';
import ApiClient from '../ApiClient';

describe('#ContactsAPI', () => {
  it('creates correct instance', () => {
    expect(contactAPI).toBeInstanceOf(ApiClient);
    expect(contactAPI).toHaveProperty('get');
    expect(contactAPI).toHaveProperty('show');
    expect(contactAPI).toHaveProperty('create');
    expect(contactAPI).toHaveProperty('update');
    expect(contactAPI).toHaveProperty('delete');
    expect(contactAPI).toHaveProperty('getConversations');
    expect(contactAPI).toHaveProperty('filter');
    expect(contactAPI).toHaveProperty('destroyAvatar');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#get', () => {
      contactAPI.get(1, 'name', 'customer-support');
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts?include_contact_inboxes=false&page=1&sort=name&labels%5B%5D=customer-support'
      );
    });

    it('#getConversations', () => {
      contactAPI.getConversations(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/1/conversations'
      );
    });

    it('#getContactableInboxes', () => {
      contactAPI.getContactableInboxes(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/1/contactable_inboxes'
      );
    });

    it('#getContactLabels', () => {
      contactAPI.getContactLabels(1);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts/1/labels');
    });

    it('#updateContactLabels', () => {
      const labels = ['support-query'];
      contactAPI.updateContactLabels(1, labels);
      expect(axiosMock.post).toHaveBeenCalledWith('/api/v1/contacts/1/labels', {
        labels,
      });
    });

    // ChatSPX: `buildContactParams` monta a query com `URLSearchParams`, que
    // percent-encoda os colchetes (`labels%5B%5D`). E a forma correta — o Rack lê as duas
    // identicamente, e URLSearchParams ainda escapa o termo de busca digitado pelo usuario,
    // o que a concatenacao de string anterior nao fazia. O spec e que ficou na forma antiga.
    it('#search', () => {
      contactAPI.search('leads', 1, 'date', 'customer-support');
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/search?include_contact_inboxes=false&page=1&sort=date&q=leads&labels%5B%5D=customer-support',
        { signal: undefined }
      );
    });

    it('#search with signal', () => {
      const controller = new AbortController();
      contactAPI.search('leads', 1, 'date', 'customer-support', {
        signal: controller.signal,
      });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/search?include_contact_inboxes=false&page=1&sort=date&q=leads&labels%5B%5D=customer-support',
        { signal: controller.signal }
      );
    });

    it('#searchForSchedule', () => {
      contactAPI.searchForSchedule({ q: 'maria', page: 2, perPage: 15 });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/search_for_schedule?q=maria&page=2&per_page=15'
      );
    });

    it('#destroyCustomAttributes', () => {
      contactAPI.destroyCustomAttributes(1, ['cloudCustomer']);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/1/destroy_custom_attributes',
        {
          custom_attributes: ['cloudCustomer'],
        }
      );
    });

    it('#importContacts', () => {
      const file = 'file';
      contactAPI.importContacts(file);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/import',
        expect.any(FormData),
        {
          headers: { 'Content-Type': 'multipart/form-data' },
        }
      );
    });

    it('#filter', () => {
      const queryPayload = {
        payload: [
          {
            attribute_key: 'email',
            filter_operator: 'contains',
            values: ['fayaz'],
            query_operator: null,
          },
        ],
      };
      contactAPI.filter(1, 'name', queryPayload);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/filter?include_contact_inboxes=false&page=1&sort=name',
        queryPayload
      );
    });

    it('#destroyAvatar', () => {
      contactAPI.destroyAvatar(1);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/contacts/1/avatar'
      );
    });
  });
});

describe('#buildContactParams', () => {
  it('returns correct string', () => {
    expect(buildContactParams(1, 'name', '', '')).toBe(
      'include_contact_inboxes=false&page=1&sort=name'
    );
    expect(buildContactParams(1, 'name', 'customer-support', '')).toBe(
      'include_contact_inboxes=false&page=1&sort=name&labels%5B%5D=customer-support'
    );
    expect(
      buildContactParams(1, 'name', 'customer-support', 'message-content')
    ).toBe(
      'include_contact_inboxes=false&page=1&sort=name&q=message-content&labels%5B%5D=customer-support'
    );
  });
});
