import {
  getFormattedPreChatFields,
  getLabel,
  getPlaceHolder,
} from '../preChat';
import en from 'dashboard/i18n/locale/en/inboxWidget.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';

// Mecanismo do aceite do bloco 0.8, item 4 (D10): os rotulos padrao do pre-chat
// saem do i18n do DASHBOARD e seguem o idioma do painel, em vez de vir do pacote
// de i18n do widget.
//
// O que estava quebrado, medido antes da correcao: o lookup antigo procurava
// `PRE_CHAT_FORM.FIELDS[item.name]` no i18n do widget, onde as chaves sao
// UPPER_SNAKE (EMAIL_ADDRESS) e o `name` do campo e camelCase (emailAddress).
// Nunca casava. Resultado: o dashboard carregava 58 locales do widget para
// alimentar codigo morto, e o campo sem placeholder gravado caia no fallback
// `item.name` — o visitante lia "emailAddress" dentro do input.
const messagesFor = locale => (locale === 'pt_BR' ? ptBR : en).INBOX_WIDGET;

// `t` de mentira com a mesma assinatura do vue-i18n: recebe o caminho da chave e
// devolve a string, ou a propria chave quando ela nao existe.
const fakeT = locale => path =>
  path.split('.').reduce((node, key) => node?.[key], {
    INBOX_WIDGET: messagesFor(locale),
  }) ?? path;

describe('preChat — rotulos padrao vindos do i18n do dashboard (D10)', () => {
  const seededByBackend = [
    // Como `web_widget.rb:84-101` semeia a inbox nova: label em ingles cravado no
    // Ruby e NENHUM placeholder.
    { name: 'emailAddress', label: 'Email Id', type: 'email' },
    { name: 'fullName', label: 'Full name', type: 'text' },
    { name: 'phoneNumber', label: 'Phone number', type: 'text' },
  ];

  it('preenche o placeholder ausente em pt-BR, em vez de mostrar o name do campo', () => {
    const fields = getFormattedPreChatFields(
      { preChatFields: seededByBackend },
      fakeT('pt_BR')
    );

    expect(fields.map(field => field.placeholder)).toEqual([
      'Por favor, digite seu e-mail',
      'Por favor, digite seu nome completo',
      'Por favor, digite seu número de telefone',
    ]);
    // O defeito de antes: o proprio identificador do campo virava placeholder.
    expect(fields.map(field => field.placeholder)).not.toContain(
      'emailAddress'
    );
  });

  it('preenche o placeholder ausente em en', () => {
    const fields = getFormattedPreChatFields(
      { preChatFields: seededByBackend },
      fakeT('en')
    );

    expect(fields.map(field => field.placeholder)).toEqual([
      'Please enter your email address',
      'Please enter your full name',
      'Please enter your phone number',
    ]);
  });

  it('preserva o rotulo que o cliente personalizou, sem traduzir por cima', () => {
    // Precedencia deliberada: `PreChatForm/Settings.vue` PERSISTE estes valores e
    // o widget os renderiza verbatim. Traduzir por cima apagaria a customizacao
    // do cliente no proximo save.
    const fields = getFormattedPreChatFields(
      {
        preChatFields: [
          {
            name: 'emailAddress',
            label: 'Seu e-mail corporativo',
            placeholder: 'nome@empresa.com.br',
          },
        ],
      },
      fakeT('pt_BR')
    );

    expect(fields[0].label).toBe('Seu e-mail corporativo');
    expect(fields[0].placeholder).toBe('nome@empresa.com.br');
  });

  it('usa o default traduzido quando o label tambem esta ausente', () => {
    const fields = getFormattedPreChatFields(
      { preChatFields: [{ name: 'fullName' }] },
      fakeT('pt_BR')
    );

    expect(fields[0].label).toBe('Nome Completo');
  });

  it('cai no name do campo para atributo personalizado, que nao tem chave i18n', () => {
    const fields = getFormattedPreChatFields(
      { preChatFields: [{ name: 'order_id' }] },
      fakeT('pt_BR')
    );

    expect(fields[0].label).toBe('order_id');
  });

  it('nunca deixa a chave crua vazar quando a traducao nao existe', () => {
    // `t` que devolve a chave, como o vue-i18n faz com chave ausente. Chave crua
    // na tela do cliente e o defeito que o item 1 deste mesmo bloco fecha; nao
    // vale reintroduzi-lo por aqui.
    const echoT = path => path;

    expect(getLabel({ key: 'fullName', label: undefined }, echoT)).toBe(
      'fullName'
    );
    expect(
      getPlaceHolder({ key: 'fullName', placeholder: undefined }, echoT)
    ).toBe('fullName');
  });
});
