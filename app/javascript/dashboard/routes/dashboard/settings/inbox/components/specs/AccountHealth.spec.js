import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import AccountHealth from '../AccountHealth.vue';

const OWN_URL = 'https://app.example.com/webhooks/whatsapp/+556635317222';
const SIBLING_URL = 'https://app.example.com/webhooks/whatsapp/+556632114876';
const THIRD_PARTY_URL =
  'https://chat.simplexsolucoes.com.br/webhooks/whatsapp/+556635317222';

const MISMATCH_KEY = 'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.URL_MISMATCH';
const CONFIGURED_KEY = 'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.CONFIGURED_SUCCESS';
const REGISTER_KEY = 'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.REGISTER_BUTTON';

const buildHealthData = ({
  registeredUrl,
  level = 'whatsapp_business_account',
  ...rest
}) => ({
  display_phone_number: '+556635317222',
  webhook_configuration: registeredUrl ? { [level]: registeredUrl } : {},
  expected_webhook_url: OWN_URL,
  ...rest,
});

const mountComponent = healthData =>
  mount(AccountHealth, {
    props: { healthData },
    global: {
      stubs: {
        ButtonV4: { template: '<button><slot /></button>' },
        Icon: { template: '<i />' },
      },
    },
  });

describe('AccountHealth webhook status', () => {
  describe('when the backend sends acceptable_webhook_urls', () => {
    it('does not flag a mismatch when the registered url belongs to a sibling on the same WABA', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: SIBLING_URL,
          acceptable_webhook_urls: [OWN_URL, SIBLING_URL],
        })
      );

      expect(wrapper.text()).toContain(CONFIGURED_KEY);
      expect(wrapper.text()).not.toContain(MISMATCH_KEY);
      expect(wrapper.text()).not.toContain(REGISTER_KEY);
    });

    it('does not flag a mismatch for a single channel whose own url is registered', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: OWN_URL,
          acceptable_webhook_urls: [OWN_URL],
        })
      );

      expect(wrapper.text()).toContain(CONFIGURED_KEY);
      expect(wrapper.text()).not.toContain(MISMATCH_KEY);
    });

    it('flags a mismatch for an unrelated third party url', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: THIRD_PARTY_URL,
          acceptable_webhook_urls: [OWN_URL, SIBLING_URL],
        })
      );

      expect(wrapper.text()).toContain(MISMATCH_KEY);
      expect(wrapper.text()).toContain(REGISTER_KEY);
    });

    it('flags a mismatch when the override comes from the application level pointing elsewhere', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: THIRD_PARTY_URL,
          level: 'application',
          acceptable_webhook_urls: [OWN_URL, SIBLING_URL],
        })
      );

      expect(wrapper.text()).toContain(MISMATCH_KEY);
    });

    it('accepts an application level override that matches a sibling url', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: SIBLING_URL,
          level: 'application',
          acceptable_webhook_urls: [OWN_URL, SIBLING_URL],
        })
      );

      expect(wrapper.text()).toContain(CONFIGURED_KEY);
    });
  });

  describe('when acceptable_webhook_urls is missing or empty', () => {
    it('falls back to the exact comparison and accepts the expected url', () => {
      const wrapper = mountComponent(
        buildHealthData({ registeredUrl: OWN_URL })
      );

      expect(wrapper.text()).toContain(CONFIGURED_KEY);
      expect(wrapper.text()).not.toContain(MISMATCH_KEY);
    });

    it('falls back to the exact comparison and flags a different url', () => {
      const wrapper = mountComponent(
        buildHealthData({ registeredUrl: SIBLING_URL })
      );

      expect(wrapper.text()).toContain(MISMATCH_KEY);
    });

    it('treats an empty list the same as a missing one', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: SIBLING_URL,
          acceptable_webhook_urls: [],
        })
      );

      expect(wrapper.text()).toContain(MISMATCH_KEY);
    });

    it('ignores a non array value', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: OWN_URL,
          acceptable_webhook_urls: null,
        })
      );

      expect(wrapper.text()).toContain(CONFIGURED_KEY);
    });
  });

  describe('when no webhook is configured at all', () => {
    it('asks for registration instead of reporting a mismatch', () => {
      const wrapper = mountComponent(
        buildHealthData({
          registeredUrl: null,
          acceptable_webhook_urls: [OWN_URL],
        })
      );

      expect(wrapper.text()).toContain(
        'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.ACTION_REQUIRED'
      );
      expect(wrapper.text()).not.toContain(MISMATCH_KEY);
      expect(wrapper.text()).toContain(REGISTER_KEY);
    });
  });
});
