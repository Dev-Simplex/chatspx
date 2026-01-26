<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { generateConversationsPDF } from 'dashboard/helper/ConversationPDFExporter';

const { t } = useI18n();
const route = useRoute();
const { currentAccount } = useAccount();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const contactsById = useMapGetter('contacts/getContactById');
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');
const currentUser = useMapGetter('getCurrentUser');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactConversations = computed(() =>
  conversations.value(route.params.contactId)
);

// Estado de seleção
const selectedConversationIds = ref(new Set());
const isExporting = ref(false);
const selectAllChecked = ref(false);
const exportProgress = ref(null);

// Contato atual
const currentContact = computed(() =>
  contactsById.value(route.params.contactId)
);

// Inboxes por ID
const inboxesById = computed(() => {
  const inboxes = {};
  contactConversations.value.forEach(conv => {
    if (conv.inboxId) {
      const inbox = stateInbox.value(conv.inboxId);
      if (inbox) {
        inboxes[conv.inboxId] = inbox;
      }
    }
  });
  return inboxes;
});

// Labels por ID
const labelsById = computed(() => {
  const labels = {};
  accountLabelsValue.value.forEach(label => {
    labels[label.id] = label;
  });
  return labels;
});

// Toggle seleção de uma conversa
const toggleConversationSelection = conversationId => {
  if (selectedConversationIds.value.has(conversationId)) {
    selectedConversationIds.value.delete(conversationId);
  } else {
    selectedConversationIds.value.add(conversationId);
  }
  updateSelectAllState();
};

// Verifica se uma conversa está selecionada
const isConversationSelected = conversationId => {
  return selectedConversationIds.value.has(conversationId);
};

// Selecionar/deselecionar todas
const toggleSelectAll = () => {
  // Verificar estado real: se todas estão selecionadas, desmarcar todas
  // Se não estão todas selecionadas, selecionar todas
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

// Atualiza o estado do checkbox "Selecionar todas"
const updateSelectAllState = () => {
  if (contactConversations.value.length === 0) {
    selectAllChecked.value = false;
    return;
  }
  selectAllChecked.value =
    selectedConversationIds.value.size === contactConversations.value.length;
};

// Contador de conversas selecionadas
const selectedCount = computed(() => selectedConversationIds.value.size);

// Limites para exportação
const MAX_CONVERSATIONS = 5;
const MAX_MESSAGES_PER_CONVERSATION = 500;
const MAX_TOTAL_MESSAGES = 2000;

// Verificar se excede limite de conversas
const exceedsConversationLimit = computed(
  () => selectedCount.value > MAX_CONVERSATIONS
);

// Exportar PDF
const exportToPDF = async () => {
  if (selectedConversationIds.value.size === 0) {
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.NO_CONVERSATIONS_SELECTED'));
    return;
  }

  // Validar limite de conversas antes de iniciar
  if (selectedCount.value > MAX_CONVERSATIONS) {
    useAlert(
      `Limite de conversas excedido. Máximo permitido: ${MAX_CONVERSATIONS}. Você selecionou: ${selectedCount.value}. Por favor, selecione menos conversas ou divida a exportação em múltiplos PDFs.`
    );
    return;
  }

  // Mostrar mensagem informativa sobre limites
  const limitInfo = `Exportando ${selectedCount.value} conversa(s). Limites: máximo ${MAX_CONVERSATIONS} conversas, ${MAX_MESSAGES_PER_CONVERSATION} mensagens por conversa, ${MAX_TOTAL_MESSAGES} mensagens no total.`;
  // eslint-disable-next-line no-console
  console.log(limitInfo);

  isExporting.value = true;
  exportProgress.value = null;
  const errors = [];

  try {
    const selectedConversations = contactConversations.value.filter(conv =>
      selectedConversationIds.value.has(conv.id)
    );

    await generateConversationsPDF({
      conversations: selectedConversations,
      contact: currentContact.value,
      inboxesById: inboxesById.value,
      labelsById: labelsById.value,
      accountLabels: accountLabelsValue.value,
      user: currentUser.value,
      account: currentAccount,
      onProgress: progressData => {
        if (progressData.errors) {
          errors.push(...progressData.errors);
          return;
        }

        exportProgress.value = progressData;

        if (progressData.status === 'error') {
          // eslint-disable-next-line no-console
          console.error(
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT_ERROR_CONVERSATION', {
              conversationId: progressData.conversationId,
              error: progressData.error,
            })
          );
        }
      },
    });

    if (errors.length > 0) {
      useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT_WARNING'));
    } else {
      useAlert(t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PDF_EXPORT_SUCCESS'));
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao exportar PDF:', error);

    // Melhorar mensagem de erro com informações sobre limites
    let errorMessage = t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.PDF_EXPORT_ERROR');
    if (error.message) {
      if (error.message.includes('Limite de conversas')) {
        errorMessage = error.message;
      } else if (error.message.includes('limite de mensagens')) {
        errorMessage = `${error.message} Limites: máximo ${MAX_CONVERSATIONS} conversas, ${MAX_MESSAGES_PER_CONVERSATION} mensagens por conversa, ${MAX_TOTAL_MESSAGES} mensagens no total.`;
      } else {
        errorMessage = `${errorMessage} ${error.message}`;
      }
    }

    useAlert(errorMessage);
  } finally {
    isExporting.value = false;
    exportProgress.value = null;
  }
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
    <!-- Cabeçalho com controles de seleção -->
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
          ({{ selectedCount }}
          {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.SELECTED') }})
        </span>
      </div>
      <Button
        :label="t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORT_PDF')"
        size="sm"
        :is-loading="isExporting"
        :disabled="
          selectedCount === 0 || isExporting || exceedsConversationLimit
        "
        @click="exportToPDF"
      />
    </div>
    <!-- Aviso sobre limite de conversas -->
    <div
      v-if="exceedsConversationLimit"
      class="px-6 py-3 bg-yellow-50 dark:bg-yellow-900/20 border-b border-yellow-200 dark:border-yellow-800"
    >
      <div
        class="flex items-start gap-2 text-sm text-yellow-800 dark:text-yellow-200"
      >
        <span class="font-semibold">⚠️ Aviso:</span>
        <span>
          Você selecionou {{ selectedCount }} conversas, mas o limite máximo é
          {{ MAX_CONVERSATIONS }}. Por favor, selecione menos conversas ou
          divida a exportação em múltiplos PDFs.
        </span>
      </div>
    </div>
    <!-- Informação sobre limites -->
    <div
      v-if="selectedCount > 0 && !exceedsConversationLimit"
      class="px-6 py-2 bg-green-50 dark:bg-green-900/20 border-b border-green-200 dark:border-green-800"
    >
      <div class="text-xs text-green-700 dark:text-green-300">
        <strong>Limites de exportação:</strong> Máximo
        {{ MAX_CONVERSATIONS }} conversas,
        {{ MAX_MESSAGES_PER_CONVERSATION }} mensagens por conversa,
        {{ MAX_TOTAL_MESSAGES }} mensagens no total.
      </div>
    </div>
    <!-- Mensagem de progresso -->
    <div
      v-if="isExporting && exportProgress"
      class="px-6 py-3 bg-n-alpha-1 dark:bg-n-alpha-3 border-b border-n-strong"
    >
      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <Spinner :size="16" />
        <span v-if="exportProgress.messagesLoaded">
          {{
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORTING_MESSAGES', {
              current: exportProgress.current,
              total: exportProgress.total,
              messagesLoaded: exportProgress.messagesLoaded,
            })
          }}
        </span>
        <span v-else>
          {{
            t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EXPORTING_CONVERSATION', {
              current: exportProgress.current,
              total: exportProgress.total,
            })
          }}
        </span>
      </div>
    </div>
    <!-- Lista de conversas -->
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
  </div>
  <p v-else class="px-6 py-10 text-sm leading-6 text-center text-n-slate-11">
    {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
  </p>
</template>
