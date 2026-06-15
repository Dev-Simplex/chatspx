<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  // 'unassigned' | 'colleague' | 'ai'
  variant: {
    type: String,
    default: 'unassigned',
  },
  // Name of the current assignee (colleague or AI) — used in the copy.
  assigneeName: {
    type: String,
    default: '',
  },
  // When the conversation has no team yet, the user must pick one before resolving.
  requiresTeam: {
    type: Boolean,
    default: false,
  },
  teams: {
    type: Array,
    default: () => [],
  },
  isBulk: {
    type: Boolean,
    default: false,
  },
  bulkCount: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const selectedTeamId = ref(null);

const teamsList = computed(() => props.teams || []);
const hasTeams = computed(() => teamsList.value.length > 0);

const canConfirm = computed(() => {
  if (!props.requiresTeam) return true;
  return selectedTeamId.value !== null && selectedTeamId.value !== 0;
});

const baseKey = 'CONVERSATION.RESOLVE_ASSIGNMENT_GATE';

const dialogTitle = computed(() => {
  if (props.isBulk) {
    return t(`${baseKey}.BULK.TITLE`, { count: props.bulkCount });
  }
  switch (props.variant) {
    case 'colleague':
      return t(`${baseKey}.COLLEAGUE.TITLE`, { name: props.assigneeName });
    case 'ai':
      return t(`${baseKey}.AI.TITLE`, { name: props.assigneeName });
    default:
      return t(`${baseKey}.UNASSIGNED.TITLE`);
  }
});

const dialogDescription = computed(() => {
  if (props.isBulk) {
    return t(`${baseKey}.BULK.DESCRIPTION`, { count: props.bulkCount });
  }
  switch (props.variant) {
    case 'colleague':
      return t(`${baseKey}.COLLEAGUE.DESCRIPTION`, {
        name: props.assigneeName,
      });
    case 'ai':
      return t(`${baseKey}.AI.DESCRIPTION`, { name: props.assigneeName });
    default:
      return t(`${baseKey}.UNASSIGNED.DESCRIPTION`);
  }
});

const confirmLabel = computed(() => t(`${baseKey}.CONFIRM`));

const handleConfirm = () => {
  if (!canConfirm.value) return;
  emit('confirm', { teamId: props.requiresTeam ? selectedTeamId.value : null });
};

const handleClose = () => {
  selectedTeamId.value = null;
  emit('close');
};

watch(
  () => props.show,
  newVal => {
    if (newVal) {
      selectedTeamId.value = null;
      dialogRef.value?.open();
    } else {
      dialogRef.value?.close();
    }
  }
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="dialogTitle"
    :description="dialogDescription"
    :cancel-button-label="t('DIALOG.BUTTONS.CANCEL')"
    :confirm-button-label="confirmLabel"
    :disable-confirm-button="!canConfirm"
    width="md"
    @confirm="handleConfirm"
    @close="handleClose"
  >
    <template v-if="requiresTeam">
      <p class="pt-2 text-sm font-medium text-n-slate-12">
        {{ t(`${baseKey}.SELECT_TEAM`) }}
      </p>
      <div v-if="!hasTeams" class="py-4 text-sm text-n-slate-11">
        {{ t('CONVERSATION.NO_TEAMS_AVAILABLE') }}
      </div>
      <div
        v-else
        class="flex max-h-[60vh] flex-col gap-2 overflow-y-auto py-3 pr-1"
      >
        <button
          v-for="team in teamsList"
          :key="team.id"
          type="button"
          class="flex items-center gap-3 p-3 text-left rounded-lg border transition-colors"
          :class="
            selectedTeamId === team.id
              ? 'border-n-green-9 bg-n-green-3'
              : 'border-n-weak hover:border-n-strong hover:bg-n-alpha-2'
          "
          @click="selectedTeamId = team.id"
        >
          <div
            class="flex items-center justify-center w-5 h-5 rounded-full border-2 transition-colors"
            :class="
              selectedTeamId === team.id
                ? 'border-n-green-9 bg-n-green-9'
                : 'border-n-slate-8'
            "
          >
            <svg
              v-if="selectedTeamId === team.id"
              class="w-3 h-3 text-white"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
          </div>
          <span class="text-sm font-medium text-n-slate-12">
            {{ team.name }}
          </span>
        </button>
      </div>
    </template>
  </Dialog>
</template>
