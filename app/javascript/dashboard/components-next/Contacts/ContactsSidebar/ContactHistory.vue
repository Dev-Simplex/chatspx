<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ExportConversationModal from 'dashboard/components-next/message/ExportConversationModal.vue';

const { t } = useI18n();
const route = useRoute();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactConversations = computed(() =>
  conversations.value(route.params.contactId)
);

const selectedConversationIds = ref(new Set());
const selectAllChecked = ref(false);
const showExportModal = ref(false);

const updateSelectAllState = () => {
  if (contactConversations.value.length === 0) {
    selectAllChecked.value = false;
    return;
  }
  selectAllChecked.value =
    selectedConversationIds.value.size === contactConversations.value.length;
};

const toggleConversationSelection = conversationId => {
  if (selectedConversationIds.value.has(conversationId)) {
    selectedConversationIds.value.delete(conversationId);
  } else {
    selectedConversationIds.value.add(conversationId);
  }
  updateSelectAllState();
};

const isConversationSelected = conversationId =>
  selectedConversationIds.value.has(conversationId);

const toggleSelectAll = () => {
  const allSelected =
    contactConversations.value.length > 0 &&
    selectedConversationIds.value.size === contactConversations.value.length;

  if (allSelected) {
    selectedConversationIds.value.clear();
    selectAllChecked.value = false;
  } else {
    contactConversations.value.forEach(conv => {
      selectedConversationIds.value.add(conv.id);
    });
    selectAllChecked.value = true;
  }
};

const selectedCount = computed(() => selectedConversationIds.value.size);

const selectedConversations = computed(() =>
  contactConversations.value.filter(conv =>
    selectedConversationIds.value.has(conv.id)
  )
);

const openExportModal = () => {
  if (selectedConversationIds.value.size === 0) {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.NO_CONVERSATIONS_SELECTED'));
    return;
  }
  showExportModal.value = true;
};
</script>

<template>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <div v-else-if="contactConversations.length > 0" class="flex flex-col">
    <!-- Header with selection controls -->
    <div
      class="flex items-center justify-between gap-4 px-6 py-3 border-b border-n-strong"
    >
      <div class="flex items-center gap-3">
        <Checkbox :model-value="selectAllChecked" @change="toggleSelectAll" />
        <span class="text-sm text-n-slate-11">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.SELECT_ALL') }}
        </span>
        <span
          v-if="selectedCount > 0"
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            `(${selectedCount} ${t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.SELECTED')})`
          }}
        </span>
      </div>
      <Button
        :label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT_PDF')"
        size="sm"
        :disabled="selectedCount === 0"
        @click="openExportModal"
      />
    </div>
    <!-- Conversation list -->
    <div
      class="divide-y divide-n-strong [&>*:hover]:!border-y-transparent [&>*:hover+*]:!border-t-transparent"
    >
      <div
        v-for="conversation in contactConversations"
        :key="conversation.id"
        class="flex items-start gap-3 px-6 py-4 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 transition-colors"
      >
        <div class="pt-1">
          <Checkbox
            :model-value="isConversationSelected(conversation.id)"
            @change="() => toggleConversationSelection(conversation.id)"
          />
        </div>
        <div
          class="flex-1 cursor-pointer"
          @click="toggleConversationSelection(conversation.id)"
        >
          <ConversationCard
            :conversation="conversation"
            :contact="contactsById(conversation.meta.sender.id)"
            :state-inbox="stateInbox(conversation.inboxId)"
            :account-labels="accountLabelsValue"
            class="rounded-none"
          />
        </div>
      </div>
    </div>
    <!-- Export Modal -->
    <ExportConversationModal
      :show="showExportModal"
      :conversations="selectedConversations"
      @close="showExportModal = false"
    />
  </div>
  <p v-else class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11">
    {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
  </p>
</template>
