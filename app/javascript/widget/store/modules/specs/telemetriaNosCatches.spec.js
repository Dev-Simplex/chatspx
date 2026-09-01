/**
 * Mecanismo de aceite do bloco 2.13 — o ELO entre os `catch` e o reporter.
 *
 * ACEITE (§2.2): «Erro forçado aparece no GlitchTip com PII removida».
 *
 * Os outros arquivos do bloco provam que o reporter FUNCIONA (unidade) e que o
 * relatório chega raspado (navegador). Falta o elo do meio: que os 14 sítios que
 * antes diziam `// Ignore error` de fato o chamam agora, e com a origem certa.
 *
 * Sem este arquivo, alguém poderia remover a chamada de um `catch` e todo o
 * resto continuaria verde — o widget voltaria a engolir o erro em silêncio com
 * a telemetria intacta e sem nada para registrar.
 *
 * A origem é assertada por VALOR, não por "foi chamado": ela é o que a triagem
 * usa para saber onde doeu, e um copiar-colar que deixe a origem do vizinho é
 * exatamente o erro que passa despercebido numa revisão.
 */
import fs from 'node:fs';
import path from 'node:path';
import { actions as acoesDeContato } from '../contacts';
import moduloDeEventos from '../events';
import { actions as acoesDeAtributos } from '../conversationAttributes';
import { actions as acoesDeRotulos } from '../conversationLabels';
import { actions as acoesDeConversa } from '../conversation/actions';
import { reportWidgetError } from 'widget/helpers/telemetry';
import ContactsAPI from 'widget/api/contacts';
import eventsAPI from 'widget/api/events';
import conversationLabelsAPI from 'widget/api/conversationLabels';
import {
  getConversationAPI,
  sendMessageAPI,
  getMessagesAPI,
  sendAttachmentAPI,
  toggleTyping,
  setUserLastSeenAt,
  setCustomAttributes as setCustomAttributesAPI,
  deleteCustomAttribute as deleteCustomAttributeAPI,
} from 'widget/api/conversation';

vi.mock('widget/helpers/telemetry', () => ({
  reportWidgetError: vi.fn(),
}));
vi.mock('widget/api/contacts');
vi.mock('widget/api/events');
vi.mock('widget/api/conversationLabels');
vi.mock('widget/api/conversation');
vi.mock('widget/api/approachEvent');

const falha = new Error('rede fora');

describe('2.13 — os `catch` que engoliam erro agora reportam', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('store/contacts#get', async () => {
    ContactsAPI.get = vi.fn(() => Promise.reject(falha));

    await acoesDeContato.get({ commit: vi.fn() });

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/contacts#get',
    });
  });

  it('store/contacts#update', async () => {
    ContactsAPI.update = vi.fn(() => Promise.reject(falha));

    await acoesDeContato.update({ dispatch: vi.fn() }, { user: {} });

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/contacts#update',
    });
  });

  it('store/events', async () => {
    eventsAPI.create = vi.fn(() => Promise.reject(falha));

    await moduloDeEventos.actions.create({}, { name: 'webwidget.triggered' });

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/events',
    });
  });

  it('cada sítio usa uma origem DIFERENTE', async () => {
    // Copiar-colar deixando a origem do vizinho é o defeito silencioso deste
    // bloco: a telemetria funciona, os números batem, e a triagem procura no
    // arquivo errado.
    ContactsAPI.get = vi.fn(() => Promise.reject(falha));
    ContactsAPI.update = vi.fn(() => Promise.reject(falha));
    ContactsAPI.setCustomAttributes = vi.fn(() => Promise.reject(falha));
    ContactsAPI.deleteCustomAttribute = vi.fn(() => Promise.reject(falha));

    await acoesDeContato.get({ commit: vi.fn() });
    await acoesDeContato.update({ dispatch: vi.fn() }, { user: {} });
    await acoesDeContato.setCustomAttributes({ dispatch: vi.fn() }, {});
    await acoesDeContato.deleteCustomAttribute({ dispatch: vi.fn() }, 'x');

    const origens = reportWidgetError.mock.calls.map(([, ctx]) => ctx.origem);
    expect(origens).toHaveLength(4);
    expect(new Set(origens).size).toBe(4);
    origens.forEach(origem => expect(origem).toMatch(/^store\/contacts#/));
  });

  it('store/conversationAttributes', async () => {
    getConversationAPI.mockImplementation(() => Promise.reject(falha));

    await acoesDeAtributos.getAttributes({ commit: vi.fn() });

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/conversationAttributes',
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // `conversation/actions.js` — os oito que continuavam mudos
  //
  // Cinco diziam literalmente `// IgnoreError` e três descartavam o `error` sem
  // dizer nada (`sendMessageWithData`, `sendAttachment`, `fetchOldConversations`
  // marcam a mensagem como falha na TELA e não registram nada em lugar nenhum).
  // Todos os oito estão no caminho quente da conversa: mensagem que não foi,
  // anexo que não subiu, histórico que não carregou, mensagem nova que não
  // sincronizou. Era exatamente onde a observabilidade mais faltava.
  // ───────────────────────────────────────────────────────────────────────────
  const contextoComConversa = () => ({
    commit: vi.fn(),
    rootGetters: { 'conversationAttributes/getConversationParams': { id: 7 } },
  });

  const origemRelatada = () => reportWidgetError.mock.calls.at(-1)[1].origem;

  it('conversation#sendMessage — a mensagem que o visitante escreveu e não foi', async () => {
    sendMessageAPI.mockRejectedValue(falha);

    await acoesDeConversa.sendMessageWithData(
      { commit: vi.fn(), rootState: {} },
      { message: { id: 1, content: 'oi', meta: {} } }
    );

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/conversation#sendMessage',
    });
  });

  it('conversation#sendAttachment', async () => {
    sendAttachmentAPI.mockRejectedValue(falha);

    await acoesDeConversa.sendAttachment(
      {
        commit: vi.fn(),
        state: { pendingCustomAttributes: {}, pendingLabels: [] },
      },
      { attachment: { thumbUrl: 'blob:x', fileType: 'image' } }
    );

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/conversation#sendAttachment',
    });
  });

  it('conversation#fetchOldConversations — histórico vazio com a tela parecendo pronta', async () => {
    getMessagesAPI.mockRejectedValue(falha);

    await acoesDeConversa.fetchOldConversations({ commit: vi.fn() }, {});

    expect(reportWidgetError).toHaveBeenCalledWith(falha, {
      origem: 'store/conversation#fetchOldConversations',
    });
  });

  it('conversation#syncLatestMessages', async () => {
    getMessagesAPI.mockRejectedValue(falha);

    await acoesDeConversa.syncLatestMessages({
      state: { lastMessageId: 3, conversations: {} },
      commit: vi.fn(),
    });

    expect(origemRelatada()).toBe('store/conversation#syncLatestMessages');
  });

  it('conversation#toggleUserTyping', async () => {
    toggleTyping.mockRejectedValue(falha);

    await acoesDeConversa.toggleUserTyping({}, { typingStatus: 'on' });

    expect(origemRelatada()).toBe('store/conversation#toggleUserTyping');
  });

  it('conversation#setUserLastSeen', async () => {
    setUserLastSeenAt.mockRejectedValue(falha);

    await acoesDeConversa.setUserLastSeen({
      commit: vi.fn(),
      getters: { getConversationSize: 2 },
    });

    expect(origemRelatada()).toBe('store/conversation#setUserLastSeen');
  });

  it('conversation#setCustomAttributes', async () => {
    setCustomAttributesAPI.mockRejectedValue(falha);

    await acoesDeConversa.setCustomAttributes(contextoComConversa(), { a: 1 });

    expect(origemRelatada()).toBe('store/conversation#setCustomAttributes');
  });

  it('conversation#deleteCustomAttribute', async () => {
    deleteCustomAttributeAPI.mockRejectedValue(falha);

    await acoesDeConversa.deleteCustomAttribute(contextoComConversa(), 'a');

    expect(origemRelatada()).toBe('store/conversation#deleteCustomAttribute');
  });

  it('não sobrou NENHUM `catch` mudo em conversation/actions.js', () => {
    // Os oito exemplos acima provam que os `catch` de HOJE reportam. Este prova
    // que não há um nono — e é a única forma de acusar o `catch` que alguém
    // acrescentar amanhã com `// IgnoreError` dentro: os exemplos por ação não
    // ficariam vermelhos, porque eles não sabem que a ação nova existe.
    //
    // Conta os dois lados de propósito. Um teste que só afirmasse "não existe
    // `IgnoreError`" passaria também num arquivo vazio; exigir que o número de
    // `catch` seja IGUAL ao número de `reportWidgetError` mede a cobertura, e o
    // número absoluto (9) denuncia o dia em que a contagem despencar.
    // `process.cwd()` e nao `import.meta.url`: o vitest transforma o modulo e o
    // `import.meta.url` que chega aqui nao e uma URL `file:` — `readFileSync`
    // recusa com "The URL must be of scheme file". A raiz do vitest e a raiz do
    // repositorio, e um caminho errado explode alto em vez de medir zero.
    const fonte = fs.readFileSync(
      path.resolve(
        process.cwd(),
        'app/javascript/widget/store/modules/conversation/actions.js'
      ),
      'utf8'
    );
    const catches = fonte.match(/\}\s*catch\s*\(/g) || [];
    const relatos = fonte.match(/reportWidgetError\(/g) || [];

    expect(catches).toHaveLength(9);
    expect(relatos).toHaveLength(9);

    // E as nove origens sao DISTINTAS. Copiar-colar deixando a origem do vizinho
    // e o defeito silencioso deste bloco: a telemetria funciona, os numeros
    // batem, e a triagem procura no arquivo errado.
    const origens = [...fonte.matchAll(/origem: '([^']+)'/g)].map(
      par => par[1]
    );
    expect(origens).toHaveLength(9);
    expect(new Set(origens).size).toBe(9);
  });

  it('store/conversationLabels#create e #destroy, com origens distintas', async () => {
    conversationLabelsAPI.create = vi.fn(() => Promise.reject(falha));
    conversationLabelsAPI.destroy = vi.fn(() => Promise.reject(falha));
    // O `create`/`destroy` só chegam à API quando já existe conversa; sem isso
    // saem cedo e nunca entram no `catch`.
    const contexto = {
      commit: vi.fn(),
      rootGetters: {
        'conversationAttributes/getConversationParams': { id: 7 },
      },
    };

    await acoesDeRotulos.create(contexto, 'rotulo');
    await acoesDeRotulos.destroy(contexto, 'rotulo');

    const origens = reportWidgetError.mock.calls.map(([, ctx]) => ctx.origem);
    expect(origens).toEqual([
      'store/conversationLabels#create',
      'store/conversationLabels#destroy',
    ]);
  });
});
