/**
 * A máquina de estados da conexão do widget — bloco 2.07.
 *
 * O aceite é sobre TEMPO, não sobre pixel: "rede cortada 10 s: nada nos
 * primeiros 3 s, faixa depois, composer utilizável; micro-queda de 1,5 s não
 * mostra nada". Por isso a decisão mora aqui, fora de qualquer componente —
 * assim ela é medida com relógio falso, em milissegundos, e não montando tela.
 *
 * POR QUE A CARÊNCIA EXISTE: uma queda de rede de 1,5 s é o caso comum de quem
 * anda com o celular — entrar no elevador, trocar de antena. Uma faixa vermelha
 * que pisca e some nesse intervalo assusta sem informar, e ensina o visitante a
 * ignorar a faixa quando ela finalmente importa.
 *
 * O COMPOSER NUNCA É BLOQUEADO. Estado de rede não desabilita campo: quem está
 * escrevendo continua escrevendo, e a mensagem entra na fila offline (2.16). Um
 * campo desabilitado por rede perde o texto que a pessoa acabou de digitar.
 */
export const CONNECTION_STATES = {
  ONLINE: 'online',
  RECONNECTING: 'reconnecting',
  OFFLINE: 'offline',
};

/** Carência antes de admitir ao visitante que há problema. */
export const RECONNECT_GRACE_MS = 3000;

/** A partir daqui não é mais "reconectando", é "offline". */
export const OFFLINE_AFTER_MS = 15000;

export const createConnectionMonitor = ({
  graceMs = RECONNECT_GRACE_MS,
  offlineAfterMs = OFFLINE_AFTER_MS,
  schedule = setTimeout,
  cancel = clearTimeout,
} = {}) => {
  let state = CONNECTION_STATES.ONLINE;
  let graceTimer = null;
  let offlineTimer = null;
  const listeners = new Set();
  const reconnectListeners = new Set();

  const emit = () => listeners.forEach(fn => fn(state));

  const setState = next => {
    if (state === next) return;
    state = next;
    emit();
  };

  const clearTimers = () => {
    if (graceTimer) cancel(graceTimer);
    if (offlineTimer) cancel(offlineTimer);
    graceTimer = null;
    offlineTimer = null;
  };

  return {
    /** O estado que a tela deve mostrar AGORA. */
    get state() {
      return state;
    },

    /** O composer segue utilizável em todo estado — ver a nota do topo. */
    get canCompose() {
      return true;
    },

    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },

    /**
     * A VOLTA da conexão, e por que ela não é `subscribe` — bloco 2.16.
     *
     * `subscribe` só fala quando o ESTADO MUDA, e é assim que ele deve ser: é
     * dele que sai a faixa, e a faixa não pode piscar numa micro-queda de 1,5 s.
     * Mas a fila offline não drena por causa de faixa nenhuma; ela drena porque
     * a rede voltou.
     *
     * A diferença é o caso comum, não o exótico: o POST da mensagem falha muito
     * antes de o WebSocket notar, e enquanto a carência de 3 s corre o estado
     * ainda é `online`. Nessa janela, `reportConnected()` NÃO muda estado
     * nenhum — `subscribe` fica mudo — e a mensagem que o visitante acabou de
     * digitar ficaria na fila até a próxima queda de verdade. Ligar a drenagem
     * a uma transição de estado seria enfileirar sem nunca drenar.
     *
     * Aqui, portanto, o ouvinte é chamado a CADA `reportConnected()`, com
     * mudança de estado ou sem. Drenar fila vazia não custa nada; não drenar
     * custa a mensagem.
     */
    onReconnected(listener) {
      reconnectListeners.add(listener);
      return () => reconnectListeners.delete(listener);
    },

    /**
     * A conexão caiu. Ninguém é avisado ainda: a carência começa aqui.
     *
     * IDEMPOTENTE, e isto é o oposto de detalhe: a carência conta da PRIMEIRA
     * queda. Reiniciá-la a cada nova queda faria a faixa nunca aparecer numa
     * rede instável — que é exatamente quando ela importa. O teste de "quedas
     * repetidas" existe por causa disso, e pegou esta implementação errada.
     */
    reportDisconnected() {
      if (state !== CONNECTION_STATES.ONLINE) return;
      if (graceTimer) return;
      graceTimer = schedule(() => {
        setState(CONNECTION_STATES.RECONNECTING);
        offlineTimer = schedule(() => {
          setState(CONNECTION_STATES.OFFLINE);
        }, offlineAfterMs - graceMs);
      }, graceMs);
    },

    /** Voltou. Se ninguém chegou a ser avisado, nada aparece — nem some. */
    reportConnected() {
      clearTimers();
      setState(CONNECTION_STATES.ONLINE);
      reconnectListeners.forEach(fn => fn());
    },

    destroy() {
      clearTimers();
      listeners.clear();
      reconnectListeners.clear();
    },
  };
};
