/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import NotificationsAPI from '../../api/notifications';

// Espelho Pinia de store/modules/notifications/* (Onda 2 P0-05).
const INBOX_SORT_OPTIONS = { newest: 'desc', oldest: 'asc' };
const sortConfig = {
  newest: (a, b) => b.created_at - a.created_at,
  oldest: (a, b) => a.created_at - b.created_at,
};

const sortComparator = (a, b, sortOrder) => {
  if (sortOrder === 'newest' || sortOrder === 'oldest') {
    return sortConfig[sortOrder](a, b, INBOX_SORT_OPTIONS[sortOrder]);
  }
  return 0;
};

export const useNotificationsStore = defineStore('notifications', {
  state: () => ({
    meta: { count: 0, currentPage: 1, unreadCount: 0 },
    records: {},
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isUpdating: false,
      isDeleting: false,
      isUpdatingUnreadCount: false,
      isAllNotificationsLoaded: false,
    },
    notificationFilters: {},
  }),

  getters: {
    getNotifications: state =>
      Object.values(state.records).sort((n1, n2) => n2.id - n1.id),
    getFilteredNotifications: state => filters => {
      const sortOrder = filters.sortOrder === 'desc' ? 'newest' : 'oldest';
      return Object.values(state.records).sort((n1, n2) =>
        sortComparator(n1, n2, sortOrder)
      );
    },
    getFilteredNotificationsV4: state => filters => {
      const sortOrder = filters.sortOrder === 'desc' ? 'newest' : 'oldest';
      const sorted = Object.values(state.records).sort((n1, n2) =>
        sortComparator(n1, n2, sortOrder)
      );
      return camelcaseKeys(sorted, { deep: true });
    },
    getNotificationById: state => id => state.records[id] || {},
    getUIFlags: state => state.uiFlags,
    getNotification: state => id => state.records[id] || {},
    getMeta: state => state.meta,
    getNotificationFilters: state => state.notificationFilters,
    getHasUnreadNotifications: state => state.meta.unreadCount > 0,
    getUnreadCount: state => state.meta.unreadCount,
  },

  actions: {
    _setNotifications(data) {
      const newRecords = { ...this.records };
      const actorIndex = {};
      Object.entries(newRecords).forEach(([id, record]) => {
        if (record.primary_actor_id) actorIndex[record.primary_actor_id] = id;
      });
      data.forEach(notification => {
        const existingId = actorIndex[notification.primary_actor_id];
        if (existingId && existingId !== String(notification.id)) {
          delete newRecords[existingId];
        }
        newRecords[notification.id] = {
          ...(newRecords[notification.id] || {}),
          ...notification,
        };
        actorIndex[notification.primary_actor_id] = notification.id;
      });
      this.records = newRecords;
    },

    _setMeta(data) {
      const {
        count,
        current_page: currentPage,
        unread_count: unreadCount,
      } = data;
      this.meta = { ...this.meta, count, currentPage, unreadCount };
    },

    _clearNotifications() {
      this.records = {};
      this.uiFlags.isAllNotificationsLoaded = false;
    },

    async get({ page = 1 } = {}) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: {
            data: { payload, meta },
          },
        } = await NotificationsAPI.get({ page });
        this._clearNotifications();
        this._setNotifications(payload);
        this._setMeta(meta);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async index({ page = 1, status, type, sortOrder } = {}) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: {
            data: { payload, meta },
          },
        } = await NotificationsAPI.get({
          page,
          status,
          type,
          sortOrder,
        });
        this._setNotifications(payload);
        this._setMeta(meta);
        if (payload.length < 15) this.uiFlags.isAllNotificationsLoaded = true;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async unReadCount() {
      this.uiFlags.isUpdatingUnreadCount = true;
      try {
        const { data } = await NotificationsAPI.getUnreadCount();
        this.meta.unreadCount = data < 0 ? 0 : data;
      } finally {
        this.uiFlags.isUpdatingUnreadCount = false;
      }
    },

    async read({ id, primaryActorType, primaryActorId, unreadCount }) {
      this.uiFlags.isUpdating = true;
      try {
        await NotificationsAPI.read(primaryActorType, primaryActorId);
        this.meta.unreadCount = unreadCount - 1 < 0 ? 0 : unreadCount - 1;
        if (this.records[id]) {
          this.records[id] = { ...this.records[id], read_at: new Date() };
        }
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async unread({ id }) {
      this.uiFlags.isUpdating = true;
      try {
        await NotificationsAPI.unRead(id);
        if (this.records[id]) {
          this.records[id] = { ...this.records[id], read_at: null };
        }
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async readAll() {
      this.uiFlags.isUpdating = true;
      try {
        await NotificationsAPI.readAll();
        this.meta.unreadCount = 0;
        const updated = {};
        Object.entries(this.records).forEach(([id, item]) => {
          updated[id] = { ...item, read_at: true };
        });
        this.records = updated;
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete({ notification, count, unreadCount }) {
      this.uiFlags.isDeleting = true;
      try {
        await NotificationsAPI.delete(notification.id);
        const newUnread = unreadCount - 1 < 0 ? 0 : unreadCount - 1;
        this.meta.unreadCount = newUnread;
        const { [notification.id]: _removed, ...rest } = this.records;
        this.records = rest;
        this.meta.count = count;
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async deleteAllRead() {
      this.uiFlags.isDeleting = true;
      try {
        await NotificationsAPI.deleteAll({ type: 'read' });
        const unread = {};
        Object.entries(this.records).forEach(([id, item]) => {
          if (!item.read_at) unread[id] = item;
        });
        this.records = unread;
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async deleteAll() {
      this.uiFlags.isDeleting = true;
      try {
        await NotificationsAPI.deleteAll({ type: 'all' });
        this.records = {};
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async snooze({ id, snoozedUntil }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await NotificationsAPI.snooze({ id, snoozedUntil });
        const {
          data: { snoozed_until = null },
        } = response;
        if (this.records[id]) {
          this.records[id] = { ...this.records[id], snoozed_until };
        }
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    updateNotification(data) {
      const { notification, unread_count: unreadCount, count } = data;
      this.records = {
        ...this.records,
        [notification.id]: {
          ...(this.records[notification.id] || {}),
          ...notification,
        },
      };
      this.meta.unreadCount = unreadCount;
      this.meta.count = count;
    },

    addNotification(data) {
      const { notification, unread_count: unreadCount, count } = data;
      this.records = {
        ...this.records,
        [notification.id]: {
          ...(this.records[notification.id] || {}),
          ...notification,
        },
      };
      this.meta.unreadCount = unreadCount;
      this.meta.count = count;
    },

    deleteNotification(data) {
      const { notification, unread_count: unreadCount, count } = data;
      const { [notification.id]: _removed, ...rest } = this.records;
      this.records = rest;
      this.meta.unreadCount = unreadCount;
      this.meta.count = count;
    },

    clear() {
      this._clearNotifications();
    },

    setNotificationFilters(filters) {
      this.notificationFilters = filters;
    },

    updateNotificationFilters(filters) {
      this.notificationFilters = { ...this.notificationFilters, ...filters };
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useNotificationsStore, import.meta.hot)
  );
}
