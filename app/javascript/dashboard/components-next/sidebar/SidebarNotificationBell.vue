<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

const emit = defineEmits(['openNotificationPanel']);

const notificationMetadata = useMapGetter('notifications/getMeta');
const route = useRoute();
const unreadCount = computed(() => {
  if (!notificationMetadata.value.unreadCount) {
    return '';
  }

  return notificationMetadata.value.unreadCount < 100
    ? `${notificationMetadata.value.unreadCount}`
    : '99+';
});

function openNotificationPanel() {
  if (route.name !== 'notifications_index') {
    emit('openNotificationPanel');
  }
}
</script>

<template>
  <button
    class="size-9 rounded-lg hover:bg-n-slate-3/50 dark:hover:bg-n-alpha-2 flex-shrink-0 grid place-content-center relative"
    @click="openNotificationPanel"
  >
    <span class="i-lucide-bell size-[18px] text-n-slate-11" />
    <span
      v-if="unreadCount"
      class="min-h-[16px] min-w-[16px] px-1 bg-n-ruby-9 rounded-full absolute -top-0.5 -right-0.5 grid place-items-center text-[10px] leading-none font-medium text-white"
    >
      {{ unreadCount }}
    </span>
  </button>
</template>
