import { createConsumer } from '@rails/actioncable';

const PRESENCE_INTERVAL = 20000;
const RECONNECT_INTERVAL = 1000;

class BaseActionCableConnector {
  static isDisconnected = false;

  constructor(app, pubsubToken, websocketHost = '') {
    const websocketURL = websocketHost ? `${websocketHost}/cable` : undefined;
    this.isDestroyed = false;
    this.reconnectTimer = null;
    this.presenceTimer = null;

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
      this.presenceTimer = setTimeout(() => {
        if (this.isDestroyed) return;
        this.subscription.updatePresence();
        this.triggerPresenceInterval();
      }, PRESENCE_INTERVAL);
    };
    this.triggerPresenceInterval();
  }

  checkConnection() {
    if (this.isDestroyed) return;
    const isConnectionActive = this.consumer.connection.isOpen();
    const isReconnected =
      BaseActionCableConnector.isDisconnected && isConnectionActive;
    if (isReconnected) {
      this.clearReconnectTimer();
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
    this.reconnectTimer = setTimeout(() => {
      this.checkConnection();
    }, RECONNECT_INTERVAL);
  };

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {};

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {};

  disconnect() {
    this.isDestroyed = true;
    this.consumer.disconnect();
    this.clearReconnectTimer();
    if (this.presenceTimer) {
      clearTimeout(this.presenceTimer);
      this.presenceTimer = null;
    }
  }

  onReceived = ({ event, data } = {}) => {
    if (this.isAValidEvent(data)) {
      if (this.events[event] && typeof this.events[event] === 'function') {
        this.events[event](data);
      }
    }
  };
}

export default BaseActionCableConnector;
