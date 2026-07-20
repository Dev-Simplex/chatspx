<script setup>
import AttendanceCard from 'dashboard/components-next/Contacts/AttendanceCard/AttendanceCard.vue';

defineProps({
  attendances: { type: Array, required: true },
  // display_id da conversa com ação em andamento (mostra o loading naquele card).
  busyId: { type: Number, default: null },
});

const emit = defineEmits([
  'openConversation',
  'assumeAttendance',
  'requestAttendance',
  'cancelRequest',
]);
</script>

<template>
  <div class="flex flex-col gap-3">
    <AttendanceCard
      v-for="attendance in attendances"
      :id="attendance.id"
      :key="attendance.id"
      :status="attendance.status"
      :created-at="attendance.createdAt"
      :last-activity-at="attendance.lastActivityAt"
      :contact="attendance.contact"
      :inbox="attendance.inbox"
      :assignee="attendance.assignee"
      :team="attendance.team"
      :can-open="attendance.canOpen"
      :can-assume="attendance.canAssume"
      :can-request="attendance.canRequest"
      :my-pending-request-id="attendance.myPendingRequestId"
      :duplicated="attendance.duplicated"
      :is-busy="busyId === attendance.id"
      @open-conversation="emit('openConversation', $event)"
      @assume-attendance="emit('assumeAttendance', $event)"
      @request-attendance="emit('requestAttendance', $event)"
      @cancel-request="emit('cancelRequest', $event)"
    />
  </div>
</template>
