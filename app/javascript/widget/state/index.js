import { createConnectionMonitor } from './connectionMonitor';
import { createLoadingGate } from './loadingGate';
import { createOfflineQueue } from 'widget/offline/queue';

/**
 * As instâncias de estado do widget — blocos 2.07 e 2.16.
 *
 * Elas moram aqui, e não em `widget/helpers/actionCable.js`, por uma razão que
 * é de grafo, não de arrumação: quem precisa LER o estado é a tela, e o
 * `actionCable.js` arrasta `BaseActionCableConnector`, o áudio de notificação,
 * a ponte de iframe e o `mitt`. Uma faixa de "sem conexão" importando o
 * connector inteiro paga esse grafo no bundle e obriga todo teste de tela a
 * montar o ActionCable para observar um booleano.
 *
 * Sendo módulo próprio, o produtor (o connector) e o consumidor (a tela)
 * dependem os dois DESTE arquivo, e de nenhum outro.
 *
 * São SINGLETONS de propósito: existe uma conexão por página e um carregamento
 * de conversa por página. Um monitor por componente daria a cada faixa a sua
 * própria carência de 3 s, e a contagem recomeçaria a cada remontagem de tela —
 * que é exatamente o que a carência existe para impedir.
 */
export const widgetConnectionMonitor = createConnectionMonitor();

export const widgetLoadingGate = createLoadingGate();

// ── A fila offline — bloco 2.16 ──────────────────────────────────────────────
//
// Terceiro singleton, pela MESMA razão dos dois de cima e por uma a mais: há
// uma rede por página, e portanto uma fila. Duas filas competindo pela volta da
// rede drenariam ao mesmo tempo e entregariam as mensagens intercaladas — que é
// exatamente o defeito que a fila existe para não ter.
//
// `widget/offline/queue` é uma fábrica pura (sem `import` de rede, de store ou
// de componente), então instanciá-la aqui não engorda o grafo que a nota do
// topo protege.
//
// Quem enfileira é `store/modules/conversation/actions.js`, na falha de rede;
// quem drena é o plugin `store/plugins/offlineQueue.js`, no `reportConnected`.

const rejectionListeners = new Set();

/**
 * Avisa quando a fila RECUSA uma intenção — digitando, presença, tipo
 * desconhecido. Não é log decorativo: é o que permite provar, em teste de tela,
 * que o "digitando" foi mesmo OFERECIDO à fila e recusado, em vez de nunca ter
 * chegado nela. Uma asserção de "nenhum digitando na volta" passa igualzinho
 * nos dois casos, e só um deles é o comportamento correto.
 *
 * @returns {Function} para de ouvir.
 */
export const onIntentRejected = ouvinte => {
  rejectionListeners.add(ouvinte);
  return () => rejectionListeners.delete(ouvinte);
};

export const widgetOfflineQueue = createOfflineQueue({
  onDrop: recusa => rejectionListeners.forEach(fn => fn(recusa)),
});
