<script setup>
import { computed, h } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import {
  messageStamp,
  dynamicTime,
  formatDurationFromSeconds,
} from 'shared/helpers/timeHelper';

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

const getClassification = (score, classificationFromBackend = null) => {
  if (classificationFromBackend && typeof classificationFromBackend === 'string') {
    const classificationMap = {
      promoter: t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' }),
      passive: t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
      detractor: t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' }),
    };
    const translated = classificationMap[classificationFromBackend.toLowerCase()];
    if (translated) return translated;
  }

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
  if (!Array.isArray(npsResponses.value) || npsResponses.value.length === 0) {
    return [];
  }

  return npsResponses.value.map(response => {
    let dateValue = response.answered_at || response.sent_at || response.created_at;
    let unixTimestamp = null;

    if (dateValue != null) {
      try {
        if (typeof dateValue === 'number' && dateValue > 0) {
          unixTimestamp = dateValue;
        } else if (typeof dateValue === 'string' && dateValue.trim() !== '') {
          const parsed = new Date(dateValue);
          if (!isNaN(parsed.getTime()) && parsed.getTime() > 0) {
            unixTimestamp = Math.floor(parsed.getTime() / 1000);
          }
        }
      } catch (e) {
        console.warn('NpsTable: Invalid date value:', dateValue, 'for response:', response.id, e);
      }
    }

    const responseDelaySeconds = Number.isFinite(response.response_delay_seconds)
      ? response.response_delay_seconds
      : null;
    const responseDelay =
      responseDelaySeconds !== null
        ? formatDurationFromSeconds(responseDelaySeconds)
        : '--';

    return {
      id: response.id,
      contact: response.contact,
      assignedAgent: response.assigned_agent,
      score: response.score,
      classification: getClassification(response.score, response.classification),
      conversationId: response.conversation_id,
      conversation: response.conversation,
      createdAgo: unixTimestamp ? dynamicTime(unixTimestamp) : '--',
      createdAt: unixTimestamp ? messageStamp(unixTimestamp, 'LLL d yyyy, h:mm a') : '--',
      responseDelay,
    };
  });
});

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
  columnHelper.accessor('responseDelay', {
    header: t('NPS_REPORTS.TABLE.HEADER.RESPONSE_DELAY', { default: 'Demora para responder' }),
    align: 'center',
    width: 160,
    cell: cellProps => {
      const value = cellProps.getValue();
      return h(
        'span',
        {
          class: 'font-medium text-n-slate-12',
        },
        value || '--'
      );
    },
  }),
  columnHelper.accessor('conversationId', {
    header: '',
    width: 100,
    cell: cellProps => h(ConversationCell, cellProps),
  }),
]);

const paginationParams = computed(() => ({
  pageIndex,
  pageSize: 25,
}));

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
