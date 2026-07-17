<script setup>
import AttendanceCard from 'dashboard/components-next/Contacts/AttendanceCard/AttendanceCard.vue';

defineProps({
  attendances: { type: Array, required: true },
  currentUserId: { type: Number, default: null },
  // display_id da conversa cujo pedido está em andamento (mostra o loading no card).
  requestingId: { type: Number, default: null },
});

const emit = defineEmits(['requestAttendance']);
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
      :current-user-id="currentUserId"
      :is-requesting="requestingId === attendance.id"
      @request-attendance="emit('requestAttendance', $event)"
    />
  </div>
</template>
