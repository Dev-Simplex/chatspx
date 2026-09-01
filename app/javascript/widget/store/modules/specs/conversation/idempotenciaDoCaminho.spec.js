/**
 * Bloco 2.15 — a chave de idempotência NO CAMINHO DO PRODUTO.
 *
 * Já existe `widget/api/specs/idempotencia.spec.js`, e ele passa. Mas ele
 * FORNECE a chave (`endPoints.sendMessage('oi', null, { echoId: 'k' })`): mede a
 * função pura, e uma função pura não é o caminho. O defeito real vivia um andar
 * acima — `sendMessageWithData` chamava a API SEM chave, e o retry do
 * `MessageRow.vue` chamava de novo SEM chave, então cada tentativa gerava uma
 * chave nova no fallback de `sendMessageAPI`. Duas chaves diferentes é o mesmo
 * que nenhuma chave: o servidor não tem como reconhecer o reenvio.
 *
 * Aqui ninguém fornece chave nenhuma. Dispara-se a ação como a tela dispara,
 * derruba-se a rede, e mede-se O QUE SAIU NO FIO nas duas tentativas.
 */
import { actions } from '../../conversation/actions';
import { API } from 'widget/helpers/axios';

vi.mock('widget/helpers/axios');

// `buildSearchParamsWithLocale` lê o locale da instância raiz do widget
// (`urlParamsHelper.js:3`). Fora do app ela não existe — o dublê é do AMBIENTE,
// não do que se mede.
beforeAll(() => {
  window.WOOT_WIDGET = { $root: { $i18n: { locale: 'pt_BR' } } };
});

const estadoDaConversa = { pendingCustomAttributes: {}, pendingLabels: [] };
const rootState = { conversationAttributes: { id: 7 }, conversation: {} };

// Só os POSTs de mensagem. O widget faz outros (telemetria, evento de
// abordagem) e contá-los mediria outra coisa.
const postsDeMensagem = () =>
  API.post.mock.calls.filter(([url]) =>
    String(url).startsWith('/api/v1/widget/messages')
  );

const postsDeConversa = () =>
  API.post.mock.calls.filter(([url]) =>
    String(url).startsWith('/api/v1/widget/conversations')
  );

// A mensagem que o `MessageRow.vue` tem em mãos quando o visitante toca no
// botão de retry: a que o store guardou com `status: 'failed'`. Ler do commit é
// o que garante a FORMA REAL — inventar o objeto aqui seria fornecer a chave de
// novo, por outro caminho.
const mensagemComStatus = (commit, status) => {
  const chamadas = commit.mock.calls.filter(
    ([mutacao, payload]) =>
      mutacao === 'pushMessageToConversation' && payload?.status === status
  );
  return chamadas.length ? chamadas[chamadas.length - 1][1] : undefined;
};

describe('2.15 — a chave sobrevive ao retry (caminho do produto)', () => {
  let commit;

  beforeEach(() => {
    commit = vi.fn();
  });

  it('o retry do MessageRow reenvia a MESMA chave — sem ela o servidor duplica', async () => {
    API.post.mockRejectedValue(new Error('rede caiu'));

    // `sendMessage` despacha `sendMessageWithData` sem aguardar; a promessa é
    // capturada aqui para que o teste não meça um envio pela metade.
    let pendente;
    const dispatch = (nome, payload) => {
      pendente = actions[nome]({ commit, rootState }, payload);
      return pendente;
    };

    await actions.sendMessage(
      { dispatch, state: estadoDaConversa },
      { content: 'bom dia' }
    );
    await pendente;

    const falhada = mensagemComStatus(commit, 'failed');
    expect(falhada).toBeDefined();

    // Exatamente o que `MessageRow.vue:230` faz.
    await actions.sendMessageWithData(
      { commit, rootState },
      { message: falhada }
    );

    const chaves = postsDeMensagem().map(
      ([, params]) => params.message.echo_id
    );

    expect(chaves).toHaveLength(2);
    expect(chaves[0]).toBeTruthy();
    expect(chaves[1]).toBe(chaves[0]);
  });

  it('a chave é o id da mensagem otimista — é o que casa a bolha com a linha do servidor', async () => {
    API.post.mockRejectedValue(new Error('rede caiu'));

    let pendente;
    const dispatch = (nome, payload) => {
      pendente = actions[nome]({ commit, rootState }, payload);
      return pendente;
    };

    await actions.sendMessage(
      { dispatch, state: estadoDaConversa },
      { content: 'bom dia' }
    );
    await pendente;

    const falhada = mensagemComStatus(commit, 'failed');
    const [[, params]] = postsDeMensagem();

    expect(params.message.echo_id).toBe(falhada.id);
  });

  it('mensagens DIFERENTES continuam com chaves diferentes — repetir de propósito é direito do visitante', async () => {
    API.post.mockRejectedValue(new Error('rede caiu'));

    const enviar = async conteudo => {
      let pendente;
      const dispatch = (nome, payload) => {
        pendente = actions[nome]({ commit, rootState }, payload);
        return pendente;
      };
      await actions.sendMessage(
        { dispatch, state: estadoDaConversa },
        { content: conteudo }
      );
      await pendente;
    };

    await enviar('oi');
    await enviar('oi');

    const chaves = postsDeMensagem().map(
      ([, params]) => params.message.echo_id
    );

    expect(chaves).toHaveLength(2);
    expect(chaves[0]).not.toBe(chaves[1]);
  });

  it('o anexo também leva chave, e ela é o id da mensagem otimista', async () => {
    API.post.mockRejectedValue(new Error('rede caiu'));

    await actions.sendAttachment(
      { commit, state: estadoDaConversa },
      {
        attachment: {
          file: new File(['conteudo'], 'nota.txt', { type: 'text/plain' }),
          thumbUrl: 'blob:thumb',
          fileType: 'file',
        },
        replyTo: null,
      }
    );

    const temporaria = mensagemComStatus(commit, 'in_progress');
    const [[, formData]] = postsDeMensagem();

    expect(temporaria).toBeDefined();
    expect(formData.get('message[echo_id]')).toBe(temporaria.id);
  });

  it('o pré-chat também leva chave — hoje ele criava conversa e mensagem sem nenhuma', async () => {
    API.post.mockResolvedValue({
      data: { id: 1, contact: {}, messages: [{ id: 10, content: 'oi' }] },
    });

    await actions.createConversation(
      { commit, dispatch: vi.fn() },
      { fullName: 'Maria', message: 'oi' }
    );

    const [[, params]] = postsDeConversa();

    expect(params.message.echo_id).toBeTruthy();
  });
});
