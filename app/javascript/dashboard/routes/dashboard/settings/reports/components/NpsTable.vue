<script setup>
import { defineEmits, computed, h } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import { messageStamp, dynamicTime } from 'shared/helpers/timeHelper';

// components
import Table from 'dashboard/components/table/Table.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import UserAvatarWithName from 'dashboard/components/widgets/UserAvatarWithName.vue';
import ConversationCell from './ConversationCell.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';

const props = defineProps({
  pageIndex: {
    type: Number,
    default: 0,
  },
  responseState: {
    type: String,
    default: 'responded',
    validator: v => ['responded', 'not_responded'].includes(v),
  },
});

const emit = defineEmits(['pageChange', 'responseStateChange']);
const { t } = useI18n();
const npsResponses = useMapGetter('npsResponses/getNpsResponses');
const metrics = useMapGetter('npsResponses/getMetrics');
const listTotalCount = useMapGetter('npsResponses/getNpsListTotalCount');

const getClassification = (score, classificationFromBackend = null) => {
  // If classification comes from backend, translate it first
  if (
    classificationFromBackend &&
    typeof classificationFromBackend === 'string'
  ) {
    const classificationMap = {
      promoter: t('NPS_REPORTS.CLASSIFICATION.PROMOTER', {
        default: 'Promotor',
      }),
      passive: t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' }),
      detractor: t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', {
        default: 'Detrator',
      }),
    };
    const translated =
      classificationMap[classificationFromBackend.toLowerCase()];
    if (translated) return translated;
  }

  // Otherwise, calculate from score
  if (score === null || score === undefined) return '--';
  if (score >= 9)
    return t('NPS_REPORTS.CLASSIFICATION.PROMOTER', { default: 'Promotor' });
  if (score >= 7)
    return t('NPS_REPORTS.CLASSIFICATION.PASSIVE', { default: 'Passivo' });
  return t('NPS_REPORTS.CLASSIFICATION.DETRACTOR', { default: 'Detrator' });
};

const getClassificationColor = score => {
  if (score === null || score === undefined) return 'text-n-slate-10';
  if (score >= 9) return 'text-green-600';
  if (score >= 7) return 'text-yellow-600';
  return 'text-red-600';
};

const tableData = computed(() => {
  if (!npsResponses.value) return [];
  let responsesArray;
  if (Array.isArray(npsResponses.value)) {
    responsesArray = npsResponses.value;
  } else if (npsResponses.value) {
    responsesArray = Array.from(npsResponses.value);
  } else {
    responsesArray = [];
  }
  if (!Array.isArray(responsesArray) || responsesArray.length === 0) return [];

  return responsesArray.map(response => {
    // Get valid date - prefer answered_at, fallback to sent_at, then created_at
    // Backend should return Unix timestamps (numbers), but handle both formats
    let dateValue =
      response.answered_at || response.sent_at || response.created_at;

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
          if (!Number.isNaN(date.getTime()) && date.getTime() > 0) {
            // Convert to Unix timestamp (seconds)
            unixTimestamp = Math.floor(date.getTime() / 1000);
          }
        }
      } catch {
        // Invalid date value — ignore
      }
    }

    return {
      id: response.id,
      contact: response.contact,
      assignedAgent: response.assigned_agent,
      score: response.score,
      classification: getClassification(
        response.score,
        response.classification
      ),
      conversationId: response.conversation_id,
      conversation: response.conversation,
      createdAgo: unixTimestamp ? dynamicTime(unixTimestamp) : '--',
      createdAt: unixTimestamp
        ? messageStamp(unixTimestamp, 'LLL d yyyy, h:mm a')
        : '--',
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
    header: t('NPS_REPORTS.TABLE.HEADER.CLASSIFICATION', {
      default: 'Classificação',
    }),
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
  columnHelper.accessor('conversationId', {
    header: '',
    width: 100,
    cell: cellProps => h(ConversationCell, cellProps),
  }),
]);

const paginationParams = computed(() => ({
  pageIndex: props.pageIndex,
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
    return listTotalCount.value > 0
      ? listTotalCount.value
      : metrics.value.total_count || 0;
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
    class="bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl overflow-hidden"
  >
    <div class="mb-4 flex items-center justify-between px-5 pt-5">
      <div
        class="inline-flex gap-1 rounded-lg border border-n-weak bg-n-solid-3 p-1"
        role="group"
        :aria-label="
          t('NPS_REPORTS.FILTER.ARIA_LABEL', {
            default: 'Filter by response status',
          })
        "
      >
        <Button
          :color="props.responseState === 'responded' ? 'blue' : 'slate'"
          :variant="props.responseState === 'responded' ? 'solid' : 'ghost'"
          size="sm"
          class="!h-8"
          @click="emit('responseStateChange', 'responded')"
        >
          {{ t('NPS_REPORTS.FILTER.RESPONDED', { default: 'Respondidos' }) }}
        </Button>
        <Button
          :color="props.responseState === 'not_responded' ? 'blue' : 'slate'"
          :variant="props.responseState === 'not_responded' ? 'solid' : 'ghost'"
          size="sm"
          class="!h-8"
          @click="emit('responseStateChange', 'not_responded')"
        >
          {{
            t('NPS_REPORTS.FILTER.NOT_RESPONDED', {
              default: 'Não respondidos',
            })
          }}
        </Button>
      </div>
    </div>
    <div v-if="tableData.length > 0" class="px-5">
      <Table
        :table="table"
        type="reports"
        class="max-h-[calc(100vh-21.875rem)]"
      />
    </div>
    <div
      v-else
      class="h-48 flex items-center justify-center text-n-slate-10 text-sm"
    >
      {{
        $t('NPS_REPORTS.NO_RECORDS', { default: 'Nenhum registro encontrado' })
      }}
    </div>
    <div
      v-if="listTotalCount > 0 || metrics.total_count > 0"
      class="flex items-center justify-between px-4 py-3 border-t border-n-weak"
    >
      <Pagination :table="table" />
    </div>
  </div>
</template>
