<script>
import { formatDate } from 'shared/helpers/DateHelper';

export default {
  props: {
    date: {
      type: String,
      required: true,
    },
  },
  computed: {
    formattedDate() {
      return formatDate({
        date: this.date,
        todayText: this.$t('TODAY'),
        yesterdayText: this.$t('YESTERDAY'),
      });
    },
  },
};
</script>

<template>
  <div
    class="flex justify-center items-center h-[50px] w-full"
  >
    <span
      class="text-xs text-n-slate-11 bg-white dark:bg-n-solid-3 rounded-lg px-3 py-1 shadow-sm"
    >
      {{ formattedDate }}
    </span>
  </div>
</template>
