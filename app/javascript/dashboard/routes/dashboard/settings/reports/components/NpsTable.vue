<script setup>
import { defineEmits, computed, h, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import { messageStamp, dynamicTime } from 'shared/helpers/timeHelper';

// components
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import UserAvatarWithName from 'dashboard/components/widgets/UserAvatarWithName.vue';
import ConversationCell from './ConversationCell.vue';

import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';

const { pageIndex } = defineProps({
  pageIndex: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['pageChange']);
const { t } = useI18n();
const npsResponses = useMapGetter('npsResponses/getNpsResponses');
const metrics = useMapGetter('npsResponses/getMetrics');

// Debug logs
watch(() => npsResponses.value, (newVal) => {
  console.log('NpsTable: npsResponses changed:', newVal);
  console.log('NpsTable: npsResponses is array?', Array.isArray(newVal));
  console.log('NpsTable: npsResponses length:', newVal?.length);
}, { immediate: true, deep: true });

watch(() => metrics.value, (newVal) => {
  console.log('NpsTable: metrics changed:', newVal);
}, { immediate: true, deep: true });

const getClassification = (score, classificationFromBackend = null) => {
  // If classification comes from backend, translate it first
  if (classificationFromBackend && typeof classificationFromBackend === 'string') {
    const classificationMap = {
      'promoter': t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' }),
      'passive': t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
      'detractor': t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' }),
    };
    const translated = classificationMap[classificationFromBackend.toLowerCase()];
    if (translated) return translated;
  }
  
  // Otherwise, calculate from score
  if (score === null || score === undefined) return '--';
  if (score >= 9) return t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' });
  if (score >= 7) return t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' });
  return t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' });
};

const getClassificationColor = (score) => {
  if (score === null || score === undefined) return 'text-n-slate-10';
  if (score >= 9) return 'text-green-600';
  if (score >= 7) return 'text-yellow-600';
  return 'text-red-600';
};

const tableData = computed(() => {
  console.log('NpsTable: tableData computed - npsResponses.value:', npsResponses.value);
  console.log('NpsTable: tableData computed - is array?', Array.isArray(npsResponses.value));
  console.log('NpsTable: tableData computed - npsResponses.value type:', typeof npsResponses.value);
  
  // Handle case where npsResponses.value might be undefined or null initially
  if (!npsResponses.value) {
    console.log('NpsTable: npsResponses.value is falsy, returning empty array');
    return [];
  }
  
  // Ensure it's an array - check if it's a Proxy or actual array
  const responsesArray = Array.isArray(npsResponses.value) 
    ? npsResponses.value 
    : (npsResponses.value && Array.from ? Array.from(npsResponses.value) : []);
  
  if (!Array.isArray(responsesArray) || responsesArray.length === 0) {
    console.log('NpsTable: responsesArray is not an array or is empty, returning empty');
    return [];
  }
  
  console.log('NpsTable: Processing', responsesArray.length, 'responses');
  const mapped = responsesArray.map(response => {
    // Get valid date - prefer answered_at, fallback to sent_at, then created_at
    // Backend should return Unix timestamps (numbers), but handle both formats
    let dateValue = response.answered_at || response.sent_at || response.created_at;
    
    // Convert date to Unix timestamp if needed
    // dynamicTime and messageStamp expect Unix timestamp (number in seconds)
    let unixTimestamp = null;
    
    if (dateValue != null && dateValue !== undefined) {
      try {
        // If it's already a number (Unix timestamp), use it directly
        if (typeof dateValue === 'number' && dateValue > 0) {
          unixTimestamp = dateValue;
        } else if (typeof dateValue === 'string' && dateValue.trim() !== '') {
          // If it's a string, try to parse it
          const date = new Date(dateValue);
          if (!isNaN(date.getTime()) && date.getTime() > 0) {
            // Convert to Unix timestamp (seconds)
            unixTimestamp = Math.floor(date.getTime() / 1000);
          }
        }
      } catch (e) {
        console.warn('NpsTable: Invalid date value:', dateValue, 'for response:', response.id, e);
      }
    }
    
    return {
      id: response.id,
      contact: response.contact,
      assignedAgent: response.assigned_agent,
      score: response.score,
      classification: getClassification(response.score, response.classification),
      comment: response.comment || null,
      conversationId: response.conversation_id,
      conversation: response.conversation,
      createdAgo: unixTimestamp ? dynamicTime(unixTimestamp) : '--',
      createdAt: unixTimestamp ? messageStamp(unixTimestamp, 'LLL d yyyy, h:mm a') : '--',
    };
  });
  console.log('NpsTable: tableData mapped result length:', mapped.length);
  console.log('NpsTable: tableData mapped result:', mapped);
  return mapped;
});

const defaultSpanRender = cellProps => {
  const value = cellProps.getValue() || '---';
  return h(
    'span',
    {
      class: 'line-clamp-5 break-words max-w-full text-n-slate-12',
      title: value,
    },
    value
  );
};

const columnHelper = createColumnHelper();

const columns = computed(() => [
  columnHelper.accessor('contact', {
    header: t('NPS_REPORTS.TABLE.HEADER.CONTACT_NAME', { default: 'Contato' }),
    width: 200,
    cell: cellProps => {
      const { contact } = cellProps.row.original;
      if (contact) {
        return h(UserAvatarWithName, {
          user: contact,
          class: 'max-w-[200px] overflow-hidden',
        });
      }
      return '--';
    },
  }),
  columnHelper.accessor('assignedAgent', {
    header: t('NPS_REPORTS.TABLE.HEADER.AGENT_NAME', { default: 'Agente' }),
    width: 200,
    cell: cellProps => {
      const { assignedAgent } = cellProps.row.original;
      if (assignedAgent) {
        return h(UserAvatarWithName, {
          user: assignedAgent,
          class: 'max-w-[200px] overflow-hidden',
        });
      }
      return '--';
    },
  }),
  columnHelper.accessor('score', {
    header: t('NPS_REPORTS.TABLE.HEADER.SCORE', { default: 'Score' }),
    align: 'center',
    width: 80,
    cell: cellProps => {
      const { score } = cellProps.row.original;
      if (score === null || score === undefined) {
        return h('span', { class: 'text-n-slate-10' }, '--');
      }
      return h(
        'span',
        {
          class: 'font-semibold text-n-slate-12',
        },
        `${score}/10`
      );
    },
  }),
  columnHelper.accessor('classification', {
    header: t('NPS_REPORTS.TABLE.HEADER.CLASSIFICATION', { default: 'Classificação' }),
    align: 'center',
    width: 120,
    cell: cellProps => {
      const { score, classification } = cellProps.row.original;
      return h(
        'span',
        {
          class: `font-medium ${getClassificationColor(score)}`,
        },
        classification || '--'
      );
    },
  }),
  columnHelper.accessor('comment', {
    header: t('NPS_REPORTS.TABLE.HEADER.COMMENT', { default: 'Comentário' }),
    width: 400,
    cell: defaultSpanRender,
  }),
  columnHelper.accessor('conversationId', {
    header: '',
    width: 100,
    cell: cellProps => h(ConversationCell, cellProps),
  }),
]);

const paginationParams = computed(() => {
  return {
    pageIndex: pageIndex,
    pageSize: 25,
  };
});

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  manualPagination: true,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
  get rowCount() {
    return metrics.value.total_count || 0;
  },
  state: {
    get pagination() {
      return paginationParams.value;
    },
  },
  onPaginationChange: updater => {
    const newPagination = updater(paginationParams.value);
    emit('pageChange', newPagination.pageIndex);
  },
});
</script>

<template>
  <div
    class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
  >
    <div v-if="tableData.length > 0">
      <Table :table="table" class="max-h-[calc(100vh-21.875rem)]" />
    </div>
    <div
      v-else
      class="h-48 flex items-center justify-center text-n-slate-12 text-sm"
    >
      {{ $t('NPS_REPORTS.NO_RECORDS', { default: 'Nenhum registro encontrado' }) }}
    </div>
    <div v-if="metrics.total_count > 0" class="table-pagination">
      <Pagination class="mt-2" :table="table" />
    </div>
  </div>
</template>
