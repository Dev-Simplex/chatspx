import { createConnectionMonitor } from './connectionMonitor';
import { createLoadingGate } from './loadingGate';

/**
 * As DUAS instâncias de estado do widget — bloco 2.07.
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
