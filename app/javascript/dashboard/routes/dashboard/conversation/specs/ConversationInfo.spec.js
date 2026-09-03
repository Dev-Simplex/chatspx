import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import ConversationInfo from '../ConversationInfo.vue';

// O componente real de atributos precisa da store; aqui so interessa o slot
// staticItem, que e onde o IP e desenhado.
const CustomAttributesStub = {
  props: ['staticElements'],
  template: `
    <div>
      <template v-for="element in staticElements" :key="element.key">
        <slot name="staticItem" :element="element" />
      </template>
    </div>
  `,
};

const mountInfo = (contactAttributes = { created_at_ip: '203.0.113.77' }) =>
  mount(ConversationInfo, {
    props: {
      conversationAttributes: {
        referer: 'https://loja.exemplo.com/carrinho',
        browser_language: 'pt',
      },
      contactAttributes,
    },
    global: {
      stubs: { CustomAttributes: CustomAttributesStub },
    },
  });

describe('ConversationInfo — IP do visitante', () => {
  it('nasce mascarado: o endereco completo nao esta em lugar nenhum do DOM', () => {
    const wrapper = mountInfo();

    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '203.•••'
    );
    expect(wrapper.html()).not.toContain('203.0.113.77');
  });

  it('revela o endereco completo depois do clique, e volta a mascarar no segundo', async () => {
    const wrapper = mountInfo();
    const toggle = wrapper.find('[data-testid="toggle-ip-address"]');

    await toggle.trigger('click');
    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '203.0.113.77'
    );

    await toggle.trigger('click');
    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '203.•••'
    );
    expect(wrapper.html()).not.toContain('203.0.113.77');
  });

  it('mascara IPv6 pelo primeiro grupo', () => {
    const wrapper = mountInfo({
      created_at_ip: '2001:db8:85a3::8a2e:370:7334',
    });

    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '2001:•••'
    );
    expect(wrapper.html()).not.toContain('8a2e');
  });

  it('nao desenha a linha de IP quando o contato nao tem endereco', () => {
    const wrapper = mountInfo({});

    expect(wrapper.find('[data-testid="ip-address-value"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="toggle-ip-address"]').exists()).toBe(
      false
    );
  });

  it('nao mexe no referer, que continua sendo um link com o valor inteiro', () => {
    const wrapper = mountInfo();
    const link = wrapper.find('a[target="_blank"]');

    expect(link.attributes('href')).toBe('https://loja.exemplo.com/carrinho');
    expect(link.text()).toBe('https://loja.exemplo.com/carrinho');
  });
  // A store de contatos cameliza o payload (mutations.js:5, camelcaseKeys deep),
  // entao o registro guarda `createdAtIp`. Enquanto o componente lia so
  // `created_at_ip`, a linha do IP nunca renderizava — o painel prometia um
  // campo que nao existia na tela.
  it('renderiza o IP tambem quando a chave chega camelizada pela store', () => {
    const wrapper = mountInfo({ createdAtIp: '198.51.100.9' });

    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '198.•••'
    );
    expect(wrapper.html()).not.toContain('198.51.100.9');
  });

  it('revela o IP camelizado no clique', async () => {
    const wrapper = mountInfo({ createdAtIp: '198.51.100.9' });

    await wrapper.find('[data-testid="toggle-ip-address"]').trigger('click');

    expect(wrapper.find('[data-testid="ip-address-value"]').text()).toBe(
      '198.51.100.9'
    );
  });
});
