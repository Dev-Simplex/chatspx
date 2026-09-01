/**
 * A fila offline do widget — bloco 2.16.
 *
 * Ela guarda INTENÇÃO, nunca estado transitório. "Enviar esta mensagem" é uma
 * intenção: continua verdadeira dez segundos depois, quando a rede volta.
 * "Estou digitando" é estado: chegar atrasado é pior que não chegar — o agente
 * veria "digitando" de alguém que parou de digitar faz meio minuto, e num lote
 * veria três avisos seguidos de um visitante que digitou uma vez.
 *
 * A ORDEM É O ACEITE: três mensagens digitadas offline chegam na ordem em que
 * foram escritas. Por isso a drenagem é SEQUENCIAL — um `Promise.all` aqui
 * entregaria as três ao mesmo tempo e o servidor as ordenaria por acaso.
 *
 * Falha no meio da drenagem PARA a fila e devolve o que sobrou para o começo:
 * perder a segunda mensagem e entregar a terceira seria pior que não entregar
 * nenhuma.
 */

/** Tipos que a fila aceita. Tudo que não estiver aqui é recusado. */
export const INTENCOES = ['send_message', 'send_attachment'];

/** Recusados explicitamente, para o erro dizer o porquê. */
const TRANSITORIOS = ['typing_on', 'typing_off', 'presence_update'];

export const createOfflineQueue = ({ onDrop = () => {} } = {}) => {
  let itens = [];
  let drenando = false;

  return {
    get size() {
      return itens.length;
    },

    /** Só para teste e diagnóstico: a fila em ordem, sem expor o array real. */
    peek() {
      return itens.map(item => ({ ...item }));
    },

    /**
     * @returns {boolean} `true` se entrou na fila; `false` se foi recusado.
     */
    enqueue(intencao) {
      const { type } = intencao ?? {};

      if (TRANSITORIOS.includes(type)) {
        // Não é erro: é o comportamento correto, e quem chamou merece saber.
        onDrop({ type, reason: 'transitorio' });
        return false;
      }
      if (!INTENCOES.includes(type)) {
        onDrop({ type, reason: 'desconhecido' });
        return false;
      }

      itens.push({ ...intencao });
      return true;
    },

    /**
     * Entrega os itens na ordem, um de cada vez.
     *
     * @param {Function} enviar recebe o item e devolve uma promessa
     * @returns {Promise<{enviados: number, restantes: number}>}
     */
    async flush(enviar) {
      // ── DUAS DRENAGENS AO MESMO TEMPO PERDEM MENSAGEM ─────────────────────
      //
      // Quem chama isto é a volta da rede, e a volta da rede NÃO acontece uma
      // vez por queda: o ActionCable reconecta em rajada, e cada
      // `reportConnected()` dispara uma drenagem. Sem esta guarda, duas
      // drenagens simultâneas leem o MESMO `itens[0]`, enviam a mesma mensagem
      // duas vezes — o que ninguém vê, porque o servidor deduplica pela chave
      // do 2.15 — e depois dão `shift()` cada uma. Some o primeiro item e some
      // o SEGUNDO, que nunca chegou a ser enviado. A perda é silenciosa e
      // definitiva: a fila já esqueceu que ele existia.
      //
      // A segunda chamada, portanto, não faz nada — e diz que não fez, em vez
      // de mentir um `{ enviados: 0, restantes: 0 }` que pareceria sucesso.
      if (drenando) {
        return { enviados: 0, restantes: itens.length, jaDrenando: true };
      }
      drenando = true;

      const enviados = [];
      try {
        while (itens.length) {
          const [proximo] = itens;
          try {
            // A ordem É o aceite: paralelizar entregaria as mensagens fora de
            // ordem, e aqui o laço sequencial é a funcionalidade, não descuido.
            // eslint-disable-next-line no-await-in-loop
            await enviar(proximo);
          } catch (error) {
            return { enviados: enviados.length, restantes: itens.length };
          }
          enviados.push(itens.shift());
        }

        return { enviados: enviados.length, restantes: 0 };
      } finally {
        drenando = false;
      }
    },

    clear() {
      itens = [];
    },
  };
};
