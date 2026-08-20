import { shallowMount, mount } from '@vue/test-utils';
import ButtonV4 from 'next/button/Button.vue';
import AccountHealth from '../AccountHealth.vue';

// RECONCILIAÇÃO — os dois lados CRIARAM este arquivo (conflito add/add), com
// exames que não se sobrepõem: navegação e formatação de um lado, status de
// webhook do outro. É união, e ela precisou de três cuidados que um `cat` dos
// dois arquivos não teria:
//
//  1. `vi.mock('vue-i18n')` estava nos DOIS. Dois mocks do mesmo módulo no mesmo
//     arquivo não somam — o último vence. Ficou o mais completo (`t` + `te` +
//     `locale`); o outro só tinha `t`, e os exames de formatação dependem de
//     `te` devolver false para provar que a chave crua não vaza na tela.
//  2. `mountComponent` também estava nos dois, com corpos diferentes
//     (`shallowMount` sem stubs × `mount` com stubs de ButtonV4/Icon). Cada um
//     ficou DENTRO do seu próprio `describe`, onde já era usado.
//  3. As constantes de URL do bloco de webhook desceram junto com ele, pelo
//     mesmo motivo.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
    te: () => false,
    locale: { value: 'en' },
  }),
}));

describe('AccountHealth', () => {
  const mountComponent = (healthData, props = {}) =>
    shallowMount(AccountHealth, {
      props: { healthData, ...props },
    });

  beforeEach(() => {
    vi.spyOn(window, 'open').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('opens the phone numbers page for the correct WhatsApp Business Account', async () => {
    const wrapper = mountComponent({
      business_account_id: 'waba-456',
      business_portfolio_id: 'business-123',
    });

    await wrapper.findComponent(ButtonV4).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://business.facebook.com/latest/whatsapp_manager/phone_numbers/?business_id=business-123&asset_id=waba-456',
      '_blank'
    );
  });

  it('opens Meta Business Manager when the WhatsApp Business Account ID is unavailable', async () => {
    const wrapper = mountComponent({
      business_portfolio_id: 'business-123',
    });

    await wrapper.findComponent(ButtonV4).trigger('click');

    expect(window.open).toHaveBeenCalledWith(
      'https://business.facebook.com/',
      '_blank'
    );
  });

  it('formats unknown messaging tiers and account modes without exposing translation keys', () => {
    const wrapper = mountComponent({
      messaging_limit_tier: 'TIER_CUSTOM',
      account_mode: 'CUSTOM_MODE',
    });

    expect(wrapper.text()).toContain('Tier Custom');
    expect(wrapper.text()).toContain('Custom Mode');
    expect(wrapper.text()).not.toContain(
      'INBOX_MGMT.ACCOUNT_HEALTH.VALUES.TIERS.TIER_CUSTOM'
    );
    expect(wrapper.text()).not.toContain(
      'INBOX_MGMT.ACCOUNT_HEALTH.VALUES.MODES.CUSTOM_MODE'
    );
  });

  it('shows the current error instead of stale health data', () => {
    const wrapper = mountComponent(
      { verified_name: 'Stale Business Name' },
      {
        healthError: {
          type: 'authorization',
          message: 'The connection needs to be refreshed',
        },
        isEmbeddedSignup: true,
      }
    );

    expect(wrapper.text()).toContain('The connection needs to be refreshed');
    expect(wrapper.text()).not.toContain('Stale Business Name');
  });
});

// ── Bloco vindo da homologação: status de webhook ────────────────────────────
describe('AccountHealth — webhook', () => {
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
});
