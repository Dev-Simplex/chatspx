<script setup>
import AttendanceCard from 'dashboard/components-next/Contacts/AttendanceCard/AttendanceCard.vue';

defineProps({
  attendances: { type: Array, required: true },
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
      @request-attendance="emit('requestAttendance', $event)"
    />
  </div>
</template>
