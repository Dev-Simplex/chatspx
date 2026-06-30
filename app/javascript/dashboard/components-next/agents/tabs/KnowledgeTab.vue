<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainDocumentAPI from 'dashboard/api/captain/document';

import AiSegmented from 'dashboard/components-next/agents-ui/AiSegmented.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';
import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiTextarea from 'dashboard/components-next/agents-ui/AiTextarea.vue';
import AiUploader from 'dashboard/components-next/agents-ui/AiUploader.vue';
import AiEmptyState from 'dashboard/components-next/agents-ui/AiEmptyState.vue';
import AiBadge from 'dashboard/components-next/agents-ui/AiBadge.vue';
import AiDropdown from 'dashboard/components-next/agents-ui/AiDropdown.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const activeSubTab = ref('documents');
const assistantId = computed(() => Number(route.params.assistantId));

const documents = computed(() => store.getters['captainDocuments/getRecords']);
const responses = computed(() => store.getters['captainResponses/getRecords']);
const isFetchingDocs = computed(
  () => store.getters['captainDocuments/getUIFlags'].fetchingList
);
const isFetchingResponses = computed(
  () => store.getters['captainResponses/getUIFlags'].fetchingList
);

const SUBTABS = computed(() => [
  { value: 'documents', label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOCUMENTS') },
  { value: 'faqs', label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQS') },
]);
const DOC_MODES = computed(() => [
  { value: 'url', label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.MODE_URL') },
  { value: 'file', label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.MODE_FILE') },
]);

const DOC_STYLE = {
  pdf: { icon: 'i-lucide-file-text', tint: '#1faa59' },
  url: { icon: 'i-lucide-link', tint: '#30b0c7' },
  text: { icon: 'i-lucide-file-edit', tint: '#af52de' },
};
const docStyle = type =>
  DOC_STYLE[type] || { icon: 'i-lucide-file', tint: '#8e8e93' };

const DOC_ACTIONS = computed(() => [
  {
    value: 'delete',
    label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DELETE'),
    icon: 'i-lucide-trash-2',
    danger: true,
  },
]);
const FAQ_ACTIONS = computed(() => [
  {
    value: 'edit',
    label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.EDIT'),
    icon: 'i-lucide-pencil',
  },
  {
    value: 'delete',
    label: t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DELETE'),
    icon: 'i-lucide-trash-2',
    danger: true,
  },
]);

// --- Criação de documento (URL ou PDF) ---
const showDocForm = ref(false);
const docMode = ref('url');
const docForm = ref({ name: '', externalLink: '' });
const docFile = ref(null);
const savingDoc = ref(false);

function onDocFile(file) {
  if (file && file.type !== 'application/pdf') {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_ONLY'));
    docFile.value = null;
    return;
  }
  if (file && file.size > 10 * 1024 * 1024) {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_TOO_BIG'));
    docFile.value = null;
    return;
  }
  docFile.value = file;
}

function resetDocForm() {
  docForm.value = { name: '', externalLink: '' };
  docFile.value = null;
  docMode.value = 'url';
  showDocForm.value = false;
}

async function createDocument() {
  if (savingDoc.value) return;
  const isFile = docMode.value === 'file';
  if (isFile && !docFile.value) return;
  if (!isFile && !docForm.value.externalLink.trim()) return;

  savingDoc.value = true;
  try {
    if (isFile) {
      await CaptainDocumentAPI.createWithFile({
        name: docForm.value.name.trim() || docFile.value.name,
        file: docFile.value,
        assistantId: assistantId.value,
      });
    } else {
      await store.dispatch('captainDocuments/create', {
        name: docForm.value.name.trim() || docForm.value.externalLink.trim(),
        externalLink: docForm.value.externalLink.trim(),
        assistantId: assistantId.value,
      });
    }
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_CREATED'));
    resetDocForm();
    store.dispatch('captainDocuments/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_CREATE_ERROR'));
  } finally {
    savingDoc.value = false;
  }
}

async function deleteDocument(id) {
  await store.dispatch('captainDocuments/delete', id);
}
function onDocAction(action, doc) {
  if (action === 'delete') deleteDocument(doc.id);
}

// --- Criação de FAQ ---
const showFaqForm = ref(false);
const faqForm = ref({ question: '', answer: '' });
const savingFaq = ref(false);

async function createFaq() {
  if (
    !faqForm.value.question.trim() ||
    !faqForm.value.answer.trim() ||
    savingFaq.value
  ) {
    return;
  }
  savingFaq.value = true;
  try {
    await store.dispatch('captainResponses/create', {
      question: faqForm.value.question.trim(),
      answer: faqForm.value.answer.trim(),
      assistantId: assistantId.value,
      status: 'approved',
    });
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_CREATED'));
    faqForm.value = { question: '', answer: '' };
    showFaqForm.value = false;
    store.dispatch('captainResponses/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_CREATE_ERROR'));
  } finally {
    savingFaq.value = false;
  }
}

onMounted(() => {
  const params = { assistantId: assistantId.value };
  store.dispatch('captainDocuments/get', params);
  store.dispatch('captainResponses/get', params);
});

// --- Edição de FAQ (inline) ---
const editingFaqId = ref(null);
const editFaqForm = ref({ question: '', answer: '' });
const savingFaqEdit = ref(false);

function startEditFaq(faq) {
  editingFaqId.value = faq.id;
  editFaqForm.value = { question: faq.question, answer: faq.answer };
}
function cancelEditFaq() {
  editingFaqId.value = null;
  editFaqForm.value = { question: '', answer: '' };
}
async function saveFaqEdit(faq) {
  if (
    !editFaqForm.value.question.trim() ||
    !editFaqForm.value.answer.trim() ||
    savingFaqEdit.value
  ) {
    return;
  }
  savingFaqEdit.value = true;
  try {
    await store.dispatch('captainResponses/update', {
      id: faq.id,
      question: editFaqForm.value.question.trim(),
      answer: editFaqForm.value.answer.trim(),
      status: faq.status,
    });
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_UPDATED'));
    cancelEditFaq();
    store.dispatch('captainResponses/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_UPDATE_ERROR'));
  } finally {
    savingFaqEdit.value = false;
  }
}

// --- Exclusão de FAQ (confirmação inline) ---
const confirmingDeleteFaqId = ref(null);
const deletingFaq = ref(false);

function onFaqAction(action, faq) {
  if (action === 'edit') startEditFaq(faq);
  if (action === 'delete') confirmingDeleteFaqId.value = faq.id;
}
async function deleteFaq(faq) {
  if (deletingFaq.value) return;
  deletingFaq.value = true;
  try {
    await store.dispatch('captainResponses/delete', faq.id);
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_DELETED'));
    confirmingDeleteFaqId.value = null;
    store.dispatch('captainResponses/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_DELETE_ERROR'));
  } finally {
    deletingFaq.value = false;
  }
}
</script>

<template>
  <div class="px-6 pt-4 pb-10 mx-auto max-w-3xl">
    <div class="flex justify-between items-center mb-4">
      <AiSegmented v-model="activeSubTab" :options="SUBTABS" />
      <AiButton
        v-if="activeSubTab === 'documents'"
        @click="showDocForm = !showDocForm"
      >
        <span class="i-lucide-plus size-4" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_DOCUMENT') }}
      </AiButton>
      <AiButton v-else @click="showFaqForm = !showFaqForm">
        <span class="i-lucide-plus size-4" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_FAQ') }}
      </AiButton>
    </div>

    <!-- Documentos -->
    <div v-if="activeSubTab === 'documents'">
      <AiCard v-if="showDocForm" class="mb-4">
        <div class="space-y-3">
          <AiSegmented v-model="docMode" :options="DOC_MODES" />
          <AiField
            v-model="docForm.name"
            :placeholder="
              t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_NAME_PLACEHOLDER')
            "
          />
          <AiField
            v-if="docMode === 'url'"
            v-model="docForm.externalLink"
            :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_URL_PLACEHOLDER')"
          />
          <AiUploader
            v-else
            accept="application/pdf,.pdf"
            :hint="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_HINT')"
            @select="onDocFile"
          />
          <div class="flex gap-2">
            <AiButton :disabled="savingDoc" @click="createDocument">
              {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
            </AiButton>
            <AiButton variant="ghost" @click="resetDocForm">
              {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
            </AiButton>
          </div>
        </div>
      </AiCard>

      <div
        v-if="isFetchingDocs"
        class="flex gap-2 items-center text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <AiEmptyState
        v-else-if="!documents.length"
        icon="i-lucide-file-text"
        :title="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_DOCUMENTS')"
      />
      <div v-else class="space-y-2.5">
        <div
          v-for="doc in documents"
          :key="doc.id"
          class="flex gap-3 items-center p-3.5 rounded-2xl border shadow-sm transition-shadow border-n-weak bg-n-solid-1 hover:shadow-md"
        >
          <span
            class="grid flex-none text-white rounded-xl place-items-center size-9"
            :style="{ background: docStyle(doc.document_type).tint }"
          >
            <span :class="docStyle(doc.document_type).icon" class="size-4" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[14px] font-bold truncate text-n-slate-12">
              {{ doc.name || doc.title }}
            </p>
            <p class="text-[12px] text-n-slate-10">{{ doc.document_type }}</p>
          </div>
          <AiDropdown :items="DOC_ACTIONS" @select="onDocAction($event, doc)" />
        </div>
      </div>
    </div>

    <!-- FAQs -->
    <div v-else>
      <AiCard v-if="showFaqForm" class="mb-4">
        <div class="space-y-3">
          <AiField
            v-model="faqForm.question"
            :placeholder="
              t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_QUESTION_PLACEHOLDER')
            "
          />
          <AiTextarea
            v-model="faqForm.answer"
            :rows="3"
            :placeholder="
              t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_ANSWER_PLACEHOLDER')
            "
          />
          <div class="flex gap-2">
            <AiButton :disabled="savingFaq" @click="createFaq">
              {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
            </AiButton>
            <AiButton variant="ghost" @click="showFaqForm = false">
              {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
            </AiButton>
          </div>
        </div>
      </AiCard>

      <div
        v-if="isFetchingResponses"
        class="flex gap-2 items-center text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <AiEmptyState
        v-else-if="!responses.length"
        icon="i-lucide-help-circle"
        :title="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_FAQS')"
      />
      <div v-else class="space-y-2.5">
        <AiCard v-for="faq in responses" :key="faq.id">
          <!-- Edição -->
          <div v-if="editingFaqId === faq.id" class="space-y-2.5">
            <AiField
              v-model="editFaqForm.question"
              :placeholder="
                t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_QUESTION_PLACEHOLDER')
              "
            />
            <AiTextarea
              v-model="editFaqForm.answer"
              :rows="3"
              :placeholder="
                t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_ANSWER_PLACEHOLDER')
              "
            />
            <div class="flex gap-2">
              <AiButton :disabled="savingFaqEdit" @click="saveFaqEdit(faq)">
                {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
              </AiButton>
              <AiButton variant="ghost" @click="cancelEditFaq">
                {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
              </AiButton>
            </div>
          </div>

          <!-- Leitura -->
          <template v-else>
            <div class="flex gap-2 justify-between items-start">
              <p class="text-[14px] font-bold text-n-slate-12">
                {{ faq.question }}
              </p>
              <div class="flex flex-none gap-1.5 items-center">
                <AiBadge
                  :variant="faq.status === 'approved' ? 'on' : 'warn'"
                  :label="
                    faq.status === 'approved'
                      ? t('CAPTAIN.AGENT_TABS.KNOWLEDGE.APPROVED')
                      : t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PENDING')
                  "
                />
                <template v-if="confirmingDeleteFaqId === faq.id">
                  <AiButton
                    variant="danger"
                    :disabled="deletingFaq"
                    @click="deleteFaq(faq)"
                  >
                    {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DELETE_CONFIRM') }}
                  </AiButton>
                  <AiButton
                    variant="ghost"
                    @click="confirmingDeleteFaqId = null"
                  >
                    {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
                  </AiButton>
                </template>
                <AiDropdown
                  v-else
                  :items="FAQ_ACTIONS"
                  @select="onFaqAction($event, faq)"
                />
              </div>
            </div>
            <p class="mt-1 text-[13px] line-clamp-2 text-n-slate-11">
              {{ faq.answer }}
            </p>
          </template>
        </AiCard>
      </div>
    </div>
  </div>
</template>
