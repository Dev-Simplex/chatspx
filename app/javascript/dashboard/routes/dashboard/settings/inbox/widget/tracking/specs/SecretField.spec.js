import { config, mount } from '@vue/test-utils';
import SecretField from '../SecretField.vue';

/**
 * O aceite mais perigoso da tela (bloco 5.06), e ele tem DOIS sentidos:
 *
 *  1. **nunca re-exibe** — o valor gravado nao volta para a tela;
 *  2. **salvar sem re-exibir nao pode APAGAR** — e esta e a metade que ja
 *     custou caro nesta base: o upstream passou a filtrar o campo na leitura,
 *     o formulario continuou reenviando o objeto inteiro, e abrir "Editar"
 *     numa integracao apagava a credencial do cliente.
 *
 * Testar so o primeiro sentido deixa passar exatamente o defeito que aconteceu.
 */
const [i18n] = config.global.plugins;
afterEach(() => {
  i18n.global.locale.value = 'en';
});

const build = (props = {}) => {
  i18n.global.locale.value = 'pt_BR';
  return mount(SecretField, {
    props: {
      label: 'Access Token',
      isDefined: true,
      definedAt: '03/08/2026',
      ...props,
    },
  });
};

describe('SecretField — sentido 1: nunca re-exibe', () => {
  it('mostra máscara e a data, nunca o valor', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="secret-mask"]').text()).toBe(
      '••••••••••••'
    );
    expect(wrapper.find('[data-testid="secret-state"]').text()).toContain(
      '03/08/2026'
    );
    // o componente nem RECEBE o valor: nao ha prop por onde ele entrar
    expect(Object.keys(SecretField.props ?? {})).not.toContain('modelValue');
    expect(Object.keys(SecretField.props ?? {})).not.toContain('value');
  });

  it('sem segredo gravado, diz que não está definido', () => {
    const wrapper = build({ isDefined: false, definedAt: '' });

    expect(wrapper.find('[data-testid="secret-state"]').text()).toContain(
      'Nenhum'
    );
    expect(wrapper.find('[data-testid="secret-mask"]').text()).toBe(
      'não definido'
    );
    // o rotulo do botao vem por prop (o NextButton e stubado globalmente): sem
    // segredo guardado ele diz "Definir", nao "Substituir"
    expect(
      wrapper.find('[data-testid="secret-replace"]').attributes('label')
    ).toBe('Definir');
  });

  it('ao trocar, o campo abre VAZIO — não preenchido com o que estava lá', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="secret-replace"]').trigger('click');

    expect(
      wrapper.find('[data-testid="secret-input"] input').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="secret-input"] input').attributes('type')
    ).toBe('password');
  });
});

describe('SecretField — sentido 2: salvar sem re-exibir NÃO apaga', () => {
  it('sem digitar nada, não emite evento nenhum', () => {
    const wrapper = build();

    // montar e nao mexer: nenhuma mudanca proposta
    expect(wrapper.emitted('change')).toBeUndefined();
  });

  it('abrir a troca e CANCELAR não emite — cancelar é "não mexa"', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="secret-replace"]').trigger('click');
    await wrapper.find('[data-testid="secret-cancel"]').trigger('click');

    expect(wrapper.emitted('change')).toBeUndefined();
    // e volta a mostrar o estado gravado, intacto
    expect(wrapper.find('[data-testid="secret-mask"]').text()).toBe(
      '••••••••••••'
    );
  });

  it('campo vazio NÃO pode ser confirmado — string vazia seria "apague"', async () => {
    const wrapper = build();
    await wrapper.find('[data-testid="secret-replace"]').trigger('click');

    await wrapper.find('[data-testid="secret-input"] input').setValue('   ');

    expect(
      wrapper.find('[data-testid="secret-confirm"]').attributes('disabled')
    ).toBeDefined();

    await wrapper.find('[data-testid="secret-confirm"]').trigger('click');
    expect(wrapper.emitted('change')).toBeUndefined();
  });

  it('só emite quando há valor NOVO de verdade', async () => {
    const wrapper = build();
    await wrapper.find('[data-testid="secret-replace"]').trigger('click');

    await wrapper
      .find('[data-testid="secret-input"] input')
      .setValue('  EAAG-token-novo  ');
    await wrapper.find('[data-testid="secret-confirm"]').trigger('click');

    expect(wrapper.emitted('change')).toHaveLength(1);
    // sem espaço em volta: espaço colado do gerenciador de senhas quebraria a API
    expect(wrapper.emitted('change')[0]).toEqual(['EAAG-token-novo']);
  });

  it('depois de confirmar, volta à máscara — não fica exibindo o que foi digitado', async () => {
    const wrapper = build();
    await wrapper.find('[data-testid="secret-replace"]').trigger('click');
    await wrapper.find('[data-testid="secret-input"] input').setValue('novo');
    await wrapper.find('[data-testid="secret-confirm"]').trigger('click');

    expect(wrapper.find('[data-testid="secret-input"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="secret-mask"]').text()).toBe(
      '••••••••••••'
    );
  });

  it('desabilitado explica por quê, e não deixa abrir a troca', async () => {
    const wrapper = build({
      disabled: true,
      disabledReason: 'A guarda de credenciais entra no bloco 5.02.',
    });

    expect(
      wrapper.find('[data-testid="secret-replace"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-testid="secret-disabled-reason"]').text()
    ).toContain('5.02');
  });
});
