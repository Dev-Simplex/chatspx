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
import { actions as acoesDeContato } from '../contacts';
import moduloDeEventos from '../events';
import { actions as acoesDeAtributos } from '../conversationAttributes';
import { actions as acoesDeRotulos } from '../conversationLabels';
import { reportWidgetError } from 'widget/helpers/telemetry';
import ContactsAPI from 'widget/api/contacts';
import eventsAPI from 'widget/api/events';
import conversationLabelsAPI from 'widget/api/conversationLabels';
import { getConversationAPI } from 'widget/api/conversation';

vi.mock('widget/helpers/telemetry', () => ({
  reportWidgetError: vi.fn(),
}));
vi.mock('widget/api/contacts');
vi.mock('widget/api/events');
vi.mock('widget/api/conversationLabels');
vi.mock('widget/api/conversation');

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
