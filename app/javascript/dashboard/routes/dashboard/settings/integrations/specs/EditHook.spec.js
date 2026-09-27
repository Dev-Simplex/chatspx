import { describe, expect, it } from 'vitest';
import EditHook from '../EditHook.vue';

describe('EditHook', () => {
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
