<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import MessageSequencesAPI from 'dashboard/api/messageSequences';
import MessageSequenceEnrollmentsAPI from 'dashboard/api/messageSequenceEnrollments';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

const sequences = ref([]);
const enrollments = ref([]);
const selectedSequenceId = ref('');
const isLoading = ref(false);
const isEnrolling = ref(false);

// The enrollment endpoints key off the conversation's DB id (not display_id).
const conversationDbId = computed(() => currentChat.value?.id);

const activeEnrollments = computed(() =>
  enrollments.value.filter(e => e.status === 'active')
);

const availableSequences = computed(() => {
  const enrolledIds = activeEnrollments.value.map(e => e.message_sequence.id);
  return sequences.value.filter(s => s.active && !enrolledIds.includes(s.id));
});

const loadData = async () => {
  if (!conversationDbId.value) return;
  isLoading.value = true;
  try {
    const [seqRes, enrRes] = await Promise.all([
      MessageSequencesAPI.get(),
      MessageSequenceEnrollmentsAPI.getForConversation(conversationDbId.value),
    ]);
    sequences.value = seqRes.data || [];
    enrollments.value = enrRes.data || [];
  } catch (error) {
    sequences.value = [];
    enrollments.value = [];
  } finally {
    isLoading.value = false;
  }
};

const enroll = async () => {
  if (!selectedSequenceId.value) return;
  isEnrolling.value = true;
  try {
    await MessageSequenceEnrollmentsAPI.enroll(
      selectedSequenceId.value,
      conversationDbId.value
    );
    useAlert(t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.ENROLLED'));
    selectedSequenceId.value = '';
    await loadData();
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.ERROR'));
  } finally {
    isEnrolling.value = false;
  }
};

const cancel = async enrollment => {
  try {
    await MessageSequenceEnrollmentsAPI.delete(enrollment.id);
    useAlert(t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.CANCELLED'));
    await loadData();
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.ERROR'));
  }
};

const stepLabel = enrollment => {
  const total = enrollment.message_sequence.steps_count;
  const current = enrollment.current_step_position || total;
  return t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.STEP_PROGRESS', {
    current,
    total,
  });
};

watch(() => props.conversationId, loadData, { immediate: true });
</script>

<template>
  <div class="px-1 py-1">
    <!-- Active enrollments -->
    <div
      v-for="enrollment in activeEnrollments"
      :key="enrollment.id"
      class="flex items-center justify-between gap-2 mb-2 px-3 py-2 rounded-lg bg-n-solid-2 border border-n-weak"
    >
      <div class="min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate">
          {{ enrollment.message_sequence.name }}
        </p>
        <p class="text-xs text-n-slate-11">{{ stepLabel(enrollment) }}</p>
      </div>
      <button
        class="flex-shrink-0 text-xs text-red-600 hover:text-red-700"
        @click="cancel(enrollment)"
      >
        {{ $t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.CANCEL') }}
      </button>
    </div>

    <!-- Enroll control -->
    <div v-if="availableSequences.length" class="flex items-center gap-2 mt-1">
      <select
        v-model="selectedSequenceId"
        class="flex-1 px-2 py-1.5 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
      >
        <option value="">
          {{ $t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.SELECT') }}
        </option>
        <option v-for="seq in availableSequences" :key="seq.id" :value="seq.id">
          {{ seq.name }}
        </option>
      </select>
      <button
        class="flex-shrink-0 px-3 py-1.5 text-sm font-semibold text-white bg-n-brand rounded-lg hover:opacity-90 disabled:opacity-50"
        :disabled="!selectedSequenceId || isEnrolling"
        @click="enroll"
      >
        {{ $t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.ENROLL') }}
      </button>
    </div>

    <p
      v-else-if="!activeEnrollments.length && !isLoading"
      class="text-xs text-n-slate-11"
    >
      {{ $t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.EMPTY') }}
    </p>
  </div>
</template>
