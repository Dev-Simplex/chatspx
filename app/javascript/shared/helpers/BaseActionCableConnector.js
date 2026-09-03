import { createConsumer } from '@rails/actioncable';
import WindowVisibilityHelper from 'dashboard/helper/AudioAlerts/WindowVisibilityHelper';

const PRESENCE_INTERVAL = 20000;
const PRESENCE_JITTER = 5000;
const BASE_RECONNECT_INTERVAL = 1000;
const MAX_RECONNECT_INTERVAL = 30000;
// How often we check whether the realtime stream has gone silent.
const STALE_CHECK_INTERVAL = 15000;
// If no inbound event arrives within this window (and the tab is visible) we
// assume the websocket is silently stale and trigger a route-specific refetch,
// removing the need for a manual F5. lastEventReceivedAt is bumped on EVERY
// received event (incl. other agents' presence), so a healthy stream rarely
// goes stale; the short window only fires when the socket is genuinely silent.
const STALE_EVENT_THRESHOLD = 25000;

class BaseActionCableConnector {
  static isDisconnected = false;

  constructor(
    app,
    pubsubToken,
    websocketHost = '',
    presenceInterval = PRESENCE_INTERVAL
  ) {
    const websocketURL = websocketHost ? `${websocketHost}/cable` : undefined;
    this.isDestroyed = false;
    this.reconnectTimer = null;
    this.presenceTimer = null;
    this.staleCheckTimer = null;
    this.reconnectAttempts = 0;
    this.lastEventReceivedAt = Date.now();

    this.consumer = createConsumer(websocketURL);
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'RoomChannel',
        pubsub_token: pubsubToken,
        account_id: app.$store.getters.getCurrentAccountId,
        user_id: app.$store.getters.getCurrentUserID,
      },
      {
        updatePresence() {
          this.perform('update_presence');
        },
        received: this.onReceived,
        connected: () => {
          // A lib acabou de (re)abrir o socket — inclusive o reopen automático
          // que o ConnectionMonitor dispara no visibilitychange. Ouvir esse
          // callback direto elimina a espera pelo poll de isOpen() com backoff
          // (que satura em 30s e é congelado em abas de fundo). Era essa espera
          // que deixava o banner "Desconectado" preso ao voltar para a aba.
          if (this.isDestroyed) return;
          this.reconnectAttempts = 0;
          this.clearReconnectTimer();
          this.checkConnection();
        },
        disconnected: () => {
          if (this.isDestroyed) return;
          BaseActionCableConnector.isDisconnected = true;
          this.onDisconnected();
          this.initReconnectTimer();
        },
      }
    );
    this.app = app;
    this.events = {};
    this.isAValidEvent = () => true;
    this.triggerPresenceInterval = () => {
      if (this.isDestroyed) return;
      const jitter = Math.random() * PRESENCE_JITTER;
      this.presenceTimer = setTimeout(() => {
        if (this.isDestroyed) return;
        this.subscription.updatePresence();
        this.triggerPresenceInterval();
      }, presenceInterval + jitter);
    };
    this.triggerPresenceInterval();
    this.triggerStaleCheckInterval();

    // Reconecta imediatamente ao voltar para a aba/janela. O ConnectionMonitor da
    // lib só cobre visibilitychange (e ~200ms depois); aqui reforçamos isso e
    // cobrimos os dois casos que a lib erra: foco de janela sem troca de aba
    // (máquina que "dormiu" com a aba em foreground) e bfcache (back/forward →
    // pageshow persisted). O gate isOpen() evita matar um handshake em voo e
    // brigar com o visibilityDidChange interno da lib.
    this.handleReturnToForeground = () => {
      if (this.isDestroyed) return;
      const conn = this.consumer.connection;
      if (conn && !conn.isOpen()) conn.reopen();
      this.reconnectAttempts = 0;
      this.clearReconnectTimer();
      this.checkConnection();
      // Gap-fill (Método D): recupera o que passou enquanto a aba esteve fora,
      // reusando o refetch por updatedWithin já existente. No-op no widget (não
      // há reconnectService no window).
      window.reconnectService?.handleRouteSpecificFetch?.();
    };
    this.onVisibilityChange = () => {
      if (
        typeof document === 'undefined' ||
        document.visibilityState === 'visible'
      ) {
        this.handleReturnToForeground();
      }
    };
    this.onPageShow = event => {
      if (event?.persisted) this.handleReturnToForeground();
    };
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', this.onVisibilityChange);
    }
    if (typeof window !== 'undefined') {
      window.addEventListener('focus', this.handleReturnToForeground);
      window.addEventListener('pageshow', this.onPageShow);
    }
  }

  // Dormant watchdog: if the realtime stream goes silent while the tab is
  // visible, refetch the current route's data instead of waiting for a manual
  // page reload. Reuses ReconnectService's existing fetch logic; presence pings
  // are outbound and never update lastEventReceivedAt.
  triggerStaleCheckInterval = () => {
    if (this.isDestroyed) return;
    this.staleCheckTimer = setTimeout(() => {
      if (this.isDestroyed) return;
      const isTabVisible =
        typeof document === 'undefined' ||
        WindowVisibilityHelper.isWindowVisible();
      const isStale =
        Date.now() - this.lastEventReceivedAt > STALE_EVENT_THRESHOLD;
      if (isTabVisible && isStale) {
        // O dashboard refaz o fetch pela rota; o WIDGET nao tem
        // `window.reconnectService` (medido: zero ocorrencias em
        // `app/javascript/widget/`), e por isso este temporizador rodava a cada
        // 15 s sem fazer nada la. `onStaleConnection` e o gancho que da a cada
        // superficie o seu proprio trabalho — bloco 2.07.
        window.reconnectService?.handleRouteSpecificFetch?.();
        this.onStaleConnection();
        this.lastEventReceivedAt = Date.now();
      }
      this.triggerStaleCheckInterval();
    }, STALE_CHECK_INTERVAL);
  };

  checkConnection() {
    if (this.isDestroyed) return;
    const isConnectionActive = this.consumer.connection.isOpen();
    const isReconnected =
      BaseActionCableConnector.isDisconnected && isConnectionActive;
    if (isReconnected) {
      this.clearReconnectTimer();
      this.reconnectAttempts = 0;
      this.onReconnect();
      BaseActionCableConnector.isDisconnected = false;
    } else {
      this.initReconnectTimer();
    }
  }

  clearReconnectTimer = () => {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  };

  initReconnectTimer = () => {
    if (this.isDestroyed) return;
    this.clearReconnectTimer();
    const jitter = Math.random() * 500;
    const delay = Math.min(
      BASE_RECONNECT_INTERVAL * 2 ** this.reconnectAttempts + jitter,
      MAX_RECONNECT_INTERVAL
    );
    this.reconnectAttempts += 1;
    this.reconnectTimer = setTimeout(() => {
      this.checkConnection();
    }, delay);
  };

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {};

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {};

  /** Chamado quando o fluxo silencia com a aba visivel. Vazio por padrao. */
  // eslint-disable-next-line class-methods-use-this
  onStaleConnection = () => {};

  disconnect() {
    this.isDestroyed = true;
    this.consumer.disconnect();
    this.clearReconnectTimer();
    if (typeof document !== 'undefined' && this.onVisibilityChange) {
      document.removeEventListener('visibilitychange', this.onVisibilityChange);
    }
    if (typeof window !== 'undefined') {
      if (this.handleReturnToForeground) {
        window.removeEventListener('focus', this.handleReturnToForeground);
      }
      if (this.onPageShow) {
        window.removeEventListener('pageshow', this.onPageShow);
      }
    }
    if (this.presenceTimer) {
      clearTimeout(this.presenceTimer);
      this.presenceTimer = null;
    }
    if (this.staleCheckTimer) {
      clearTimeout(this.staleCheckTimer);
      this.staleCheckTimer = null;
    }
  }

  onReceived = ({ event, data } = {}) => {
    // Single chokepoint for all inbound events: mark the stream as alive.
    this.lastEventReceivedAt = Date.now();
    if (this.isAValidEvent(data)) {
      if (this.events[event] && typeof this.events[event] === 'function') {
        this.events[event](data);
      }
    }
  };
}

export default BaseActionCableConnector;
