<script setup>
import { computed } from 'vue';
import BaseCell from 'dashboard/components/table/BaseCell.vue';

const props = defineProps({
  row: {
    type: Object,
    required: true,
  },
});

const conversationId = computed(() => props.row?.original?.conversationId);
</script>

<template>
  <BaseCell>
    <a
      v-if="conversationId"
      :href="`/app/accounts/${$route.params.accountId}/conversations/${conversationId}`"
      class="flex items-center text-xs gap-0.5 text-n-slate-11 hover:text-n-brand hover:underline whitespace-nowrap"
      target="_blank"
      rel="noopener noreferrer nofollow"
    >
      <span>#{{ conversationId }}</span>
    </a>
    <span v-else class="text-xs text-n-slate-10">--</span>
  </BaseCell>
</template>
