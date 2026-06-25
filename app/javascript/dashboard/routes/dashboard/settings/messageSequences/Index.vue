<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MessageSequencesAPI from 'dashboard/api/messageSequences';

const { t } = useI18n();

const sequences = ref([]);
const isLoading = ref(false);
const isEditing = ref(false);
const isSaving = ref(false);
const showDeletePopup = ref(false);
const deleteTarget = ref(null);

const DELAY_UNITS = { minutes: 1, hours: 60, days: 1440 };

const blankStep = () => ({
  id: null,
  content: '',
  delayValue: 0,
  delayUnit: 'minutes',
});

const form = reactive({
  id: null,
  name: '',
  active: true,
  exitOnReply: true,
  exitStatus: '',
  steps: [blankStep()],
});

const isValid = computed(
  () => form.name.trim() && form.steps.some(s => s.content.trim())
);

const loadSequences = async () => {
  isLoading.value = true;
  try {
    const { data } = await MessageSequencesAPI.get();
    sequences.value = data || [];
  } catch (error) {
    useAlert(t('MESSAGE_SEQUENCES.MESSAGES.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const splitDelay = minutes => {
  if (minutes && minutes % DELAY_UNITS.days === 0) {
    return { delayValue: minutes / DELAY_UNITS.days, delayUnit: 'days' };
  }
  if (minutes && minutes % DELAY_UNITS.hours === 0) {
    return { delayValue: minutes / DELAY_UNITS.hours, delayUnit: 'hours' };
  }
  return { delayValue: minutes || 0, delayUnit: 'minutes' };
};

const resetForm = () => {
  form.id = null;
  form.name = '';
  form.active = true;
  form.exitOnReply = true;
  form.exitStatus = '';
  form.steps = [blankStep()];
};

const openCreate = () => {
  resetForm();
  isEditing.value = true;
};

const openEdit = sequence => {
  form.id = sequence.id;
  form.name = sequence.name;
  form.active = sequence.active;
  form.exitOnReply = sequence.exit_conditions?.on_customer_reply !== false;
  form.exitStatus = sequence.exit_conditions?.on_status || '';
  form.steps = (sequence.steps || []).map(step => ({
    id: step.id,
    content: step.content || '',
    ...splitDelay(step.delay_minutes),
  }));
  if (!form.steps.length) form.steps = [blankStep()];
  isEditing.value = true;
};

const addStep = () => form.steps.push(blankStep());
const removeStep = index => {
  form.steps.splice(index, 1);
  if (!form.steps.length) form.steps.push(blankStep());
};

const buildPayload = () => {
  const exitConditions = { on_customer_reply: form.exitOnReply };
  if (form.exitStatus) exitConditions.on_status = form.exitStatus;
  return {
    name: form.name.trim(),
    active: form.active,
    exit_conditions: exitConditions,
    steps_attributes: form.steps
      .filter(step => step.content.trim() || step.id)
      .map((step, index) => ({
        id: step.id || undefined,
        position: index + 1,
        delay_minutes:
          Number(step.delayValue || 0) * DELAY_UNITS[step.delayUnit],
        content: step.content.trim(),
      })),
  };
};

const save = async () => {
  if (!isValid.value) {
    useAlert(t('MESSAGE_SEQUENCES.FORM.NEED_STEP'));
    return;
  }
  isSaving.value = true;
  try {
    const payload = buildPayload();
    if (form.id) {
      await MessageSequencesAPI.update(form.id, payload);
      useAlert(t('MESSAGE_SEQUENCES.MESSAGES.UPDATED'));
    } else {
      await MessageSequencesAPI.create(payload);
      useAlert(t('MESSAGE_SEQUENCES.MESSAGES.CREATED'));
    }
    isEditing.value = false;
    await loadSequences();
  } catch (error) {
    useAlert(t('MESSAGE_SEQUENCES.MESSAGES.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const openDelete = sequence => {
  deleteTarget.value = sequence;
  showDeletePopup.value = true;
};

const confirmDelete = async () => {
  try {
    await MessageSequencesAPI.delete(deleteTarget.value.id);
    useAlert(t('MESSAGE_SEQUENCES.MESSAGES.DELETED'));
    await loadSequences();
  } catch (error) {
    useAlert(t('MESSAGE_SEQUENCES.MESSAGES.ERROR'));
  } finally {
    showDeletePopup.value = false;
    deleteTarget.value = null;
  }
};

onMounted(loadSequences);
</script>

<template>
  <div class="flex-1 overflow-auto bg-n-solid-1">
    <div class="max-w-4xl mx-auto px-6 py-8">
      <!-- Header -->
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-bold text-n-slate-12">
            {{ $t('MESSAGE_SEQUENCES.TITLE') }}
          </h1>
          <p class="text-sm text-n-slate-11 mt-1 max-w-2xl">
            {{ $t('MESSAGE_SEQUENCES.DESCRIPTION') }}
          </p>
        </div>
        <button
          v-if="!isEditing"
          class="flex-shrink-0 inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-n-brand rounded-lg hover:opacity-90 transition-opacity"
          @click="openCreate"
        >
          <div class="i-lucide-plus size-4" />
          <span>{{ $t('MESSAGE_SEQUENCES.NEW') }}</span>
        </button>
      </div>

      <!-- Editor -->
      <div
        v-if="isEditing"
        class="bg-n-solid-2 rounded-lg border border-n-weak p-6 space-y-5"
      >
        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ $t('MESSAGE_SEQUENCES.FORM.NAME_LABEL') }}
          </label>
          <input
            v-model="form.name"
            type="text"
            class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
            :placeholder="$t('MESSAGE_SEQUENCES.FORM.NAME_PLACEHOLDER')"
          />
        </div>

        <div class="flex flex-wrap gap-6">
          <label class="flex items-center gap-2 text-sm text-n-slate-12">
            <input v-model="form.active" type="checkbox" />
            {{ $t('MESSAGE_SEQUENCES.FORM.ACTIVE_LABEL') }}
          </label>
          <label class="flex items-center gap-2 text-sm text-n-slate-12">
            <input v-model="form.exitOnReply" type="checkbox" />
            {{ $t('MESSAGE_SEQUENCES.FORM.EXIT_REPLY_LABEL') }}
          </label>
        </div>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ $t('MESSAGE_SEQUENCES.FORM.EXIT_STATUS_LABEL') }}
          </label>
          <select
            v-model="form.exitStatus"
            class="px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">
              {{ $t('MESSAGE_SEQUENCES.FORM.EXIT_STATUS_NONE') }}
            </option>
            <option value="resolved">
              {{ $t('MESSAGE_SEQUENCES.FORM.STATUS_RESOLVED') }}
            </option>
          </select>
        </div>

        <!-- Steps -->
        <div>
          <h3 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ $t('MESSAGE_SEQUENCES.FORM.STEPS_TITLE') }}
          </h3>
          <div
            v-for="(step, index) in form.steps"
            :key="index"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-4 mb-3"
          >
            <div class="flex items-center justify-between mb-2">
              <span class="text-xs font-semibold text-n-slate-11 uppercase">
                {{ $t('MESSAGE_SEQUENCES.FORM.STEP', { index: index + 1 }) }}
              </span>
              <button
                class="text-xs text-red-600 hover:text-red-700"
                @click="removeStep(index)"
              >
                {{ $t('MESSAGE_SEQUENCES.FORM.REMOVE_STEP') }}
              </button>
            </div>
            <div class="flex items-end gap-2 mb-2">
              <div>
                <label class="block text-xs text-n-slate-11 mb-1">
                  {{ $t('MESSAGE_SEQUENCES.FORM.DELAY_LABEL') }}
                </label>
                <input
                  v-model.number="step.delayValue"
                  type="number"
                  min="0"
                  class="w-24 px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </div>
              <select
                v-model="step.delayUnit"
                class="px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
              >
                <option value="minutes">
                  {{ $t('MESSAGE_SEQUENCES.FORM.UNIT_MINUTES') }}
                </option>
                <option value="hours">
                  {{ $t('MESSAGE_SEQUENCES.FORM.UNIT_HOURS') }}
                </option>
                <option value="days">
                  {{ $t('MESSAGE_SEQUENCES.FORM.UNIT_DAYS') }}
                </option>
              </select>
            </div>
            <p class="text-xs text-n-slate-11 mb-2">
              {{ $t('MESSAGE_SEQUENCES.FORM.DELAY_HELP') }}
            </p>
            <textarea
              v-model="step.content"
              rows="3"
              class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
              :placeholder="$t('MESSAGE_SEQUENCES.FORM.CONTENT_PLACEHOLDER')"
            />
            <p class="text-xs text-n-slate-11 mt-1">
              {{ $t('MESSAGE_SEQUENCES.FORM.CONTENT_HELP') }}
            </p>
          </div>
          <button
            class="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-n-slate-12 bg-n-solid-3 hover:bg-n-alpha-2 rounded-lg"
            @click="addStep"
          >
            <div class="i-lucide-plus size-4" />
            {{ $t('MESSAGE_SEQUENCES.FORM.ADD_STEP') }}
          </button>
        </div>

        <div class="flex gap-2 pt-2 border-t border-n-weak">
          <button
            class="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-n-brand rounded-lg hover:opacity-90 disabled:opacity-50"
            :disabled="isSaving"
            @click="save"
          >
            {{ $t('MESSAGE_SEQUENCES.FORM.SAVE') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12"
            @click="isEditing = false"
          >
            {{ $t('MESSAGE_SEQUENCES.FORM.CANCEL') }}
          </button>
        </div>
      </div>

      <!-- List -->
      <div v-else>
        <div v-if="isLoading" class="text-center py-16 text-n-slate-11">
          {{ $t('MESSAGE_SEQUENCES.LOADING') }}
        </div>
        <div
          v-else-if="!sequences.length"
          class="text-center py-16 text-n-slate-11"
        >
          {{ $t('MESSAGE_SEQUENCES.EMPTY') }}
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="sequence in sequences"
            :key="sequence.id"
            class="flex items-center justify-between gap-4 bg-n-solid-2 rounded-lg border border-n-weak p-4"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <h3 class="text-base font-semibold text-n-slate-12 truncate">
                  {{ sequence.name }}
                </h3>
                <span
                  class="px-2 py-0.5 text-xs font-medium rounded-full"
                  :class="
                    sequence.active
                      ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                      : 'bg-n-slate-3 text-n-slate-11'
                  "
                >
                  {{
                    sequence.active
                      ? $t('MESSAGE_SEQUENCES.ACTIVE')
                      : $t('MESSAGE_SEQUENCES.INACTIVE')
                  }}
                </span>
              </div>
              <p class="text-sm text-n-slate-11 mt-1">
                {{
                  $t('MESSAGE_SEQUENCES.STEPS_COUNT', {
                    count: (sequence.steps || []).length,
                  })
                }}
                <span v-if="sequence.enrollment_stats" class="ml-1">
                  ·
                  {{
                    $t('MESSAGE_SEQUENCES.STATS', {
                      active: sequence.enrollment_stats.active,
                      completed: sequence.enrollment_stats.completed,
                    })
                  }}
                </span>
              </p>
            </div>
            <div class="flex items-center gap-2 flex-shrink-0">
              <button
                class="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-n-slate-12 bg-n-solid-3 hover:bg-n-alpha-2 rounded-lg"
                @click="openEdit(sequence)"
              >
                <div class="i-lucide-pencil size-4" />
                {{ $t('MESSAGE_SEQUENCES.EDIT') }}
              </button>
              <button
                class="inline-flex items-center justify-center px-3 py-2 text-red-700 hover:text-red-800 bg-red-50 hover:bg-red-100 dark:text-red-300 dark:bg-red-900/20 rounded-lg"
                @click="openDelete(sequence)"
              >
                <div class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <woot-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :on-close="() => (showDeletePopup = false)"
      :on-confirm="confirmDelete"
      :title="$t('MESSAGE_SEQUENCES.DELETE')"
      :message="$t('MESSAGE_SEQUENCES.DELETE_CONFIRM')"
      :confirm-text="$t('MESSAGE_SEQUENCES.DELETE')"
      :reject-text="$t('MESSAGE_SEQUENCES.FORM.CANCEL')"
    />
  </div>
</template>
