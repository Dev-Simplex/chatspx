import { describe, expect, it } from 'vitest';
import EditHook from '../EditHook.vue';

describe('EditHook', () => {
  it('never pre-fills the Captador secret and submits only an explicitly entered rotation', () => {
    const settings = {
      shared_secret: 'private',
      shared_secret_configured: true,
    };
    const formItems = [{ name: 'shared_secret', type: 'password' }];
    const values = EditHook.methods.parseInitialValues.call({
      integrationId: 'captador',
      integration: { settings_form_schema: formItems },
      hook: { settings },
    });
    expect(values).toEqual({ shared_secret: '' });
    expect(
      EditHook.methods.buildHookPayload.call({ values, formItems })
    ).toEqual({ settings: { shared_secret: '' } });
    values.shared_secret = 'new secret';
    expect(
      EditHook.methods.buildHookPayload.call({ values, formItems })
    ).toEqual({ settings: { shared_secret: 'new secret' } });
    expect(settings.shared_secret).toBe('private');
  });

  it('deixa o segredo já configurado opcional sem afrouxar a criação', () => {
    const schema = [{ name: 'shared_secret', validation: 'required' }];

    expect(
      EditHook.computed.formItems.call({
        integration: { settings_form_schema: schema },
        hook: { settings: { shared_secret_configured: true } },
      })
    ).toEqual([{ name: 'shared_secret', validation: '' }]);
    expect(
      EditHook.computed.formItems.call({
        integration: { settings_form_schema: schema },
        hook: { settings: {} },
      })
    ).toBe(schema);
  });
});
