import { widgetConnectionMonitor } from 'widget/state';

/**
 * O fio que faltava — bloco 2.16.
 *
 * `widget/offline/queue.js` existia, com sete exemplos verdes, e ninguém o
 * chamava: `grep createOfflineQueue` achava só o módulo e o próprio spec. Uma
 * fila que ninguém instancia, ninguém enfileira e ninguém drena é código morto
 * com teste verde — o pior estado possível, porque o verde diz que está pronto.
 *
 * Este plugin é o pedaço que faltava do circuito. Ele mora aqui, e não dentro
 * de `widget/state`, por dependência: `widget/state` é lido pela TELA (a faixa
 * de conexão do 2.07 e o esqueleto), e a nota daquele arquivo protege o grafo
 * dele justamente para que uma faixa de "sem conexão" não arraste o store
 * inteiro. Fazer o `widget/state` conhecer o store inverteria isso e fecharia
 * um ciclo — o store já importa `widget/state` para enfileirar.
 *
 * Plugin de Vuex, e não uma chamada solta no boot, porque é aqui que a
 * instância do store existe sem que ninguém precise importá-la: o mesmo
 * `ligarFilaOffline` serve o store de produção e o de teste, então o teste de
 * tela mede ESTE fio, e não uma cópia dele escrita no arquivo do spec.
 *
 * `onReconnected` e não `subscribe`: a drenagem não depende de o visitante ter
 * chegado a VER a faixa. Ver a nota em `state/connectionMonitor.js`.
 */
export const ligarFilaOffline = store =>
  widgetConnectionMonitor.onReconnected(() =>
    store.dispatch('conversation/drainOfflineQueue')
  );

export default ligarFilaOffline;
