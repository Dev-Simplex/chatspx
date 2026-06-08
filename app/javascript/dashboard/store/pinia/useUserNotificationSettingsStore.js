/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import UserNotificationSettings from '../../api/userNotificationSettings';

// Espelho Pinia de store/modules/userNotificationSettings.js (Onda 2 P0-05).
export const useUserNotificationSettingsStore = defineStore(
  'userNotificationSettings',
  {
    state: () => ({
      record: {},
      uiFlags: {
        isFetching: false,
        isUpdating: false,
      },
    }),

    getters: {
      getUIFlags: state => state.uiFlags,
      getSelectedEmailFlags: state => state.record.selected_email_flags,
      getSelectedPushFlags: state => state.record.selected_push_flags,
    },

    actions: {
      async get() {
        this.uiFlags.isFetching = true;
        try {
          const response = await UserNotificationSettings.get();
          this.record = response.data;
        } finally {
          this.uiFlags.isFetching = false;
        }
      },

      async update({ selectedEmailFlags, selectedPushFlags }) {
        this.uiFlags.isUpdating = true;
        try {
          const response = await UserNotificationSettings.update({
            notification_settings: {
              selected_email_flags: selectedEmailFlags,
              selected_push_flags: selectedPushFlags,
            },
          });
          this.record = response.data;
        } catch (error) {
          throw error;
        } finally {
          this.uiFlags.isUpdating = false;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useUserNotificationSettingsStore, import.meta.hot)
  );
}
