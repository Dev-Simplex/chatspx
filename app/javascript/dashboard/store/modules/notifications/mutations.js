import types from '../../mutation-types';

export const mutations = {
  [types.SET_NOTIFICATIONS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.CLEAR_NOTIFICATIONS]: $state => {
    $state.records = {};
    $state.uiFlags.isAllNotificationsLoaded = false;
  },
  [types.SET_NOTIFICATIONS_META]: ($state, data) => {
    const {
      count,
      current_page: currentPage,
      unread_count: unreadCount,
    } = data;

    $state.meta = { ...$state.meta, count, currentPage, unreadCount };
  },
  [types.SET_NOTIFICATIONS_UNREAD_COUNT]: ($state, count) => {
    $state.meta.unreadCount = count < 0 ? 0 : count;
  },
  [types.SET_NOTIFICATIONS]: ($state, data) => {
    const newRecords = { ...$state.records };
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
    $state.records = newRecords;
  },
  [types.READ_NOTIFICATION]: ($state, { id, read_at }) => {
    if (!$state.records[id]) return;
    $state.records[id] = { ...$state.records[id], read_at };
  },
  [types.UPDATE_ALL_NOTIFICATIONS]: $state => {
    const updated = {};
    Object.entries($state.records).forEach(([id, item]) => {
      updated[id] = { ...item, read_at: true };
    });
    $state.records = updated;
  },

  [types.ADD_NOTIFICATION]($state, data) {
    const { notification, unread_count: unreadCount, count } = data;

    $state.records = {
      ...$state.records,
      [notification.id]: {
        ...($state.records[notification.id] || {}),
        ...notification,
      },
    };
    $state.meta.unreadCount = unreadCount;
    $state.meta.count = count;
  },
  [types.UPDATE_NOTIFICATION]($state, data) {
    const { notification, unread_count: unreadCount, count } = data;
    $state.records = {
      ...$state.records,
      [notification.id]: {
        ...($state.records[notification.id] || {}),
        ...notification,
      },
    };
    $state.meta.unreadCount = unreadCount;
    $state.meta.count = count;
  },
  [types.DELETE_NOTIFICATION]($state, data) {
    const { notification, unread_count: unreadCount, count } = data;
    const { [notification.id]: _, ...rest } = $state.records;
    $state.records = rest;
    $state.meta.unreadCount = unreadCount;
    $state.meta.count = count;
  },
  [types.SET_ALL_NOTIFICATIONS_LOADED]: $state => {
    $state.uiFlags.isAllNotificationsLoaded = true;
  },

  [types.DELETE_READ_NOTIFICATIONS]: $state => {
    const unread = {};
    Object.entries($state.records).forEach(([id, item]) => {
      if (!item.read_at) {
        unread[id] = item;
      }
    });
    $state.records = unread;
  },
  [types.DELETE_ALL_NOTIFICATIONS]: $state => {
    $state.records = {};
  },

  [types.SNOOZE_NOTIFICATION]: ($state, { id, snoozed_until }) => {
    if (!$state.records[id]) return;
    $state.records[id] = { ...$state.records[id], snoozed_until };
  },

  [types.SET_NOTIFICATION_FILTERS]: ($state, filters) => {
    $state.notificationFilters = filters;
  },
  [types.UPDATE_NOTIFICATION_FILTERS]: ($state, filters) => {
    $state.notificationFilters = {
      ...$state.notificationFilters,
      ...filters,
    };
  },
};
