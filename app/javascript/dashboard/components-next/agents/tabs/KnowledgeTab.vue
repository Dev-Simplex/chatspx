<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainDocumentAPI from 'dashboard/api/captain/document';

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

const DOC_TYPE_ICONS = {
  pdf: 'i-lucide-file-text',
  url: 'i-lucide-link',
  text: 'i-lucide-file-edit',
};

function docTypeIcon(docType) {
  return DOC_TYPE_ICONS[docType] || 'i-lucide-file';
}

// --- Criacao de documento (URL ou PDF) ---
const showDocForm = ref(false);
const docMode = ref('url'); // 'url' | 'file'
const docForm = ref({ name: '', externalLink: '' });
const docFile = ref(null);
const savingDoc = ref(false);

function handleFileChange(event) {
  const file = event.target.files?.[0] || null;
  if (file && file.type !== 'application/pdf') {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_ONLY'));
    event.target.value = '';
    docFile.value = null;
    return;
  }
  if (file && file.size > 10 * 1024 * 1024) {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_TOO_BIG'));
    event.target.value = '';
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

// --- Criacao de FAQ ---
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

async function deleteDocument(id) {
  await store.dispatch('captainDocuments/delete', id);
}

// --- Edicao de FAQ (inline) ---
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

// --- Exclusao de FAQ (confirmacao inline) ---
const confirmingDeleteFaqId = ref(null);
const deletingFaq = ref(false);

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
  <div class="p-6">
    <!-- Sub-tab toggle -->
    <div class="mb-4 flex gap-1 border-b border-n-weak">
      <button
        type="button"
        class="border-b-2 px-3 py-2 text-sm transition-colors"
        :class="
          activeSubTab === 'documents'
            ? 'border-n-brand font-semibold text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeSubTab = 'documents'"
      >
        <i
          class="i-lucide-file-text mr-1.5 inline-block size-3.5 align-text-bottom"
        />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOCUMENTS') }}
      </button>
      <button
        type="button"
        class="border-b-2 px-3 py-2 text-sm transition-colors"
        :class="
          activeSubTab === 'faqs'
            ? 'border-n-brand font-semibold text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeSubTab = 'faqs'"
      >
        <i
          class="i-lucide-help-circle mr-1.5 inline-block size-3.5 align-text-bottom"
        />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQS') }}
      </button>
    </div>

    <!-- Documents -->
    <div v-if="activeSubTab === 'documents'">
      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95"
          @click="showDocForm = !showDocForm"
        >
          <i class="i-lucide-plus size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_DOCUMENT') }}
        </button>
      </div>

      <div
        v-if="showDocForm"
        class="mb-4 space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <!-- Toggle URL / Arquivo -->
        <div class="flex gap-1 rounded-lg bg-n-alpha-2 p-0.5 text-sm">
          <button
            type="button"
            class="flex-1 rounded-md px-3 py-1 transition-colors"
            :class="
              docMode === 'url'
                ? 'bg-white font-medium text-n-slate-12 dark:bg-n-solid-3'
                : 'text-n-slate-10'
            "
            @click="docMode = 'url'"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.MODE_URL') }}
          </button>
          <button
            type="button"
            class="flex-1 rounded-md px-3 py-1 transition-colors"
            :class="
              docMode === 'file'
                ? 'bg-white font-medium text-n-slate-12 dark:bg-n-solid-3'
                : 'text-n-slate-10'
            "
            @click="docMode = 'file'"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.MODE_FILE') }}
          </button>
        </div>

        <input
          v-model="docForm.name"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_NAME_PLACEHOLDER')"
        />
        <input
          v-if="docMode === 'url'"
          v-model="docForm.externalLink"
          type="url"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_URL_PLACEHOLDER')"
        />
        <div v-else>
          <input
            type="file"
            accept="application/pdf,.pdf"
            class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm text-n-slate-11 file:mr-3 file:rounded file:border-0 file:bg-n-alpha-2 file:px-3 file:py-1 file:text-n-slate-12 dark:bg-n-solid-3"
            @change="handleFileChange"
          />
          <p class="mt-1 text-xs text-n-slate-9">
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PDF_HINT') }}
          </p>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
            :disabled="savingDoc"
            @click="createDocument"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="resetDocForm"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
          </button>
        </div>
      </div>

      <div
        v-if="isFetchingDocs"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <i class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <div v-else-if="!documents.length" class="py-16 text-center">
        <i class="i-lucide-file-text mx-auto mb-4 size-12 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_DOCUMENTS') }}
        </p>
      </div>
      <div v-else class="space-y-3">
        <div
          v-for="doc in documents"
          :key="doc.id"
          class="flex items-center justify-between rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
        >
          <div class="flex items-center gap-3">
            <div
              class="flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
            >
              <i
                class="size-4 text-n-slate-11"
                :class="docTypeIcon(doc.document_type)"
              />
            </div>
            <div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ doc.name || doc.title }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ doc.document_type }}
              </p>
            </div>
          </div>
          <button
            type="button"
            class="rounded-lg p-2 text-n-slate-10 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-900/20 dark:hover:text-red-400"
            @click="deleteDocument(doc.id)"
          >
            <i class="i-lucide-trash-2 size-3.5" />
          </button>
        </div>
      </div>
    </div>

    <!-- FAQs -->
    <div v-if="activeSubTab === 'faqs'">
      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95"
          @click="showFaqForm = !showFaqForm"
        >
          <i class="i-lucide-plus size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_FAQ') }}
        </button>
      </div>

      <div
        v-if="showFaqForm"
        class="mb-4 space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <input
          v-model="faqForm.question"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_QUESTION_PLACEHOLDER')
          "
        />
        <textarea
          v-model="faqForm.answer"
          rows="3"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_ANSWER_PLACEHOLDER')"
        />
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
            :disabled="savingFaq"
            @click="createFaq"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="showFaqForm = false"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
          </button>
        </div>
      </div>

      <div
        v-if="isFetchingResponses"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <i class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <div v-else-if="!responses.length" class="py-16 text-center">
        <i class="i-lucide-help-circle mx-auto mb-4 size-12 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_FAQS') }}
        </p>
      </div>
      <div v-else class="space-y-3">
        <div
          v-for="faq in responses"
          :key="faq.id"
          class="rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
        >
          <!-- Modo edicao -->
          <div v-if="editingFaqId === faq.id" class="space-y-2">
            <input
              v-model="editFaqForm.question"
              type="text"
              class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
              :placeholder="
                t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_QUESTION_PLACEHOLDER')
              "
            />
            <textarea
              v-model="editFaqForm.answer"
              rows="3"
              class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
              :placeholder="
                t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_ANSWER_PLACEHOLDER')
              "
            />
            <div class="flex gap-2">
              <button
                type="button"
                class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
                :disabled="savingFaqEdit"
                @click="saveFaqEdit(faq)"
              >
                {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
              </button>
              <button
                type="button"
                class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
                @click="cancelEditFaq"
              >
                {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
              </button>
            </div>
          </div>

          <!-- Modo leitura -->
          <template v-else>
            <div class="flex items-start justify-between gap-2">
              <p class="text-sm font-medium text-n-slate-12">
                {{ faq.question }}
              </p>
              <div class="flex shrink-0 items-center gap-1">
                <span
                  class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium"
                  :class="
                    faq.status === 'approved'
                      ? 'bg-green-50 text-green-700 dark:bg-green-400/10 dark:text-green-400'
                      : 'bg-amber-50 text-amber-700 dark:bg-amber-400/10 dark:text-amber-400'
                  "
                >
                  <span
                    class="size-1.5 rounded-full"
                    :class="
                      faq.status === 'approved' ? 'bg-green-500' : 'bg-amber-500'
                    "
                  />
                  {{
                    faq.status === 'approved'
                      ? t('CAPTAIN.AGENT_TABS.KNOWLEDGE.APPROVED')
                      : t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PENDING')
                  }}
                </span>

                <!-- Confirmacao de exclusao inline -->
                <template v-if="confirmingDeleteFaqId === faq.id">
                  <button
                    type="button"
                    class="rounded-lg px-2 py-1 text-xs font-medium text-red-600 transition-colors hover:bg-red-50 disabled:opacity-60 dark:text-red-400 dark:hover:bg-red-900/20"
                    :disabled="deletingFaq"
                    @click="deleteFaq(faq)"
                  >
                    {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DELETE_CONFIRM') }}
                  </button>
                  <button
                    type="button"
                    class="rounded-lg px-2 py-1 text-xs text-n-slate-11 transition-colors hover:bg-n-alpha-2"
                    @click="confirmingDeleteFaqId = null"
                  >
                    {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
                  </button>
                </template>
                <!-- Acoes editar / excluir -->
                <template v-else>
                  <button
                    type="button"
                    class="rounded-lg p-1.5 text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
                    :title="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.EDIT')"
                    @click="startEditFaq(faq)"
                  >
                    <i class="i-lucide-pencil size-3.5" />
                  </button>
                  <button
                    type="button"
                    class="rounded-lg p-1.5 text-n-slate-10 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-900/20 dark:hover:text-red-400"
                    :title="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DELETE')"
                    @click="confirmingDeleteFaqId = faq.id"
                  >
                    <i class="i-lucide-trash-2 size-3.5" />
                  </button>
                </template>
              </div>
            </div>
            <p class="mt-1 line-clamp-2 text-sm text-n-slate-10">
              {{ faq.answer }}
            </p>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
