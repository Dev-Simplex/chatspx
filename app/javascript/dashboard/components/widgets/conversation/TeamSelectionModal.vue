<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  show: {
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
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();
const selectedTeamId = ref(null);

const dialogRef = ref(null);

const teamsList = computed(() => {
  return props.teams || [];
});

const hasTeams = computed(() => {
  return teamsList.value.length > 0;
});

const canConfirm = computed(() => {
  return selectedTeamId.value !== null && selectedTeamId.value !== 0;
});

const dialogTitle = computed(() => {
  if (props.title) return props.title;
  return t('CONVERSATION.SELECT_TEAM_TITLE');
});

const dialogDescription = computed(() => {
  if (props.description) return props.description;
  return props.isBulk
    ? t('CONVERSATION.BULK_RESOLVE_REQUIRES_TEAM')
    : t('CONVERSATION.SELECT_TEAM_TO_RESOLVE');
});

const handleConfirm = () => {
  if (canConfirm.value) {
    emit('confirm', selectedTeamId.value);
  }
};

const handleClose = () => {
  selectedTeamId.value = null;
  emit('close');
};

// Watch show prop to open/close dialog
watch(
  () => props.show,
  newVal => {
    if (newVal) {
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
    :confirm-button-label="t('DIALOG.BUTTONS.CONFIRM')"
    :disable-confirm-button="!canConfirm"
    width="md"
    @confirm="handleConfirm"
    @close="handleClose"
  >
    <div v-if="!hasTeams" class="py-4 text-sm text-n-slate-11">
      {{ t('CONVERSATION.NO_TEAMS_AVAILABLE') }}
    </div>
    <div
      v-else
      class="flex max-h-[60vh] flex-col gap-2 overflow-y-auto py-4 pr-1"
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
        <span class="text-sm font-medium text-n-slate-12">{{ team.name }}</span>
      </button>
    </div>
  </Dialog>
</template>
