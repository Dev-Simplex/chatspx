<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { debounce, getMaxUploadSizeByChannel } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { DirectUpload } from 'activestorage';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FileUpload from 'vue-upload-component';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import ContactAPI from 'dashboard/api/contacts';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import {
  checkFileSizeLimit,
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  resolveMaximumFileUploadSize,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversation: {
    type: Object,
    default: null,
  },
  scheduledMessage: {
    type: Object,
    default: null,
  },
  requireConversation: {
    type: Boolean,
    default: false,
  },
  funnelId: {
    type: Number,
    default: null,
  },
  selectedDate: {
    type: Date,
    default: null,
  },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  message: '',
  scheduledAt: '',
  inboxId: null,
  conversationId: null,
  contactId: null,
});

const searchQuery = ref('');
const searchResults = ref([]);
const isSearching = ref(false);
const selectedContact = ref(null);
const selectedConversation = ref(null);
const contactConversations = ref([]);
const isFetchingConversations = ref(false);
const attachedFiles = ref([]);
const uploadCount = ref(0);
// Removido - não precisamos mais mostrar lista de conversas

const inboxes = computed(() => store.getters['kanban/getWahaInboxes']);
const isEditMode = computed(() => !!props.scheduledMessage?.id);
const isLoading = computed(() => {
  const uiFlags = store.getters['kanban/getUIFlags'];
  return isEditMode.value ? uiFlags.isUpdating : uiFlags.isCreating;
});
const globalConfig = computed(() => store.getters['globalConfig/get']);
const currentUser = computed(() => store.getters['getCurrentUser']);
const accountId = computed(() => store.getters['getCurrentAccountId']);
const directUploadsEnabled = computed(
  () => globalConfig.value?.directUploadsEnabled
);
const installationLimit = computed(() =>
  resolveMaximumFileUploadSize(globalConfig.value?.maximumFileUploadSize)
);
const isUploadingAttachments = computed(() => uploadCount.value > 0);
const dialogTitle = computed(() =>
  isEditMode.value
    ? t('KANBAN.SCHEDULED_MESSAGES.EDIT')
    : t('KANBAN.SCHEDULED_MESSAGES.CREATE')
);
const submitButtonLabel = computed(() =>
  isEditMode.value
    ? t('KANBAN.SCHEDULED_MESSAGES.SAVE_CHANGES')
    : t('KANBAN.SCHEDULED_MESSAGES.SCHEDULE')
);

const showContactSelector = computed(() => {
  return !isEditMode.value && !props.requireConversation && !props.conversation;
});

// Informações do contato quando há conversation
const contactInfo = computed(() => {
  if (props.conversation) {
    const contact = props.conversation.contact;
    return {
      name: getContactName(contact),
      phone: getContactPhone(contact),
      avatar: getContactAvatar(contact),
    };
  }
  if (selectedContact.value) {
    return {
      name: getContactName(selectedContact.value),
      phone: getContactPhone(selectedContact.value),
      avatar: getContactAvatar(selectedContact.value),
    };
  }
  return null;
});

const activeConversationId = computed(() => {
  return props.conversation?.id || formData.value.conversationId;
});

const activeInboxId = computed(() => {
  return (
    formData.value.inboxId ||
    props.conversation?.inboxId ||
    props.conversation?.inbox_id ||
    selectedConversation.value?.inbox_id
  );
});

const activeInbox = computed(() => {
  if (!activeInboxId.value) return null;
  return (
    inboxes.value.find(inbox => inbox.id === activeInboxId.value) ||
    props.conversation?.inbox ||
    selectedConversation.value?.inbox ||
    null
  );
});

const maxSizeFor = mime => {
  const channelType = activeInbox.value?.channel_type;

  if (!channelType || channelType === INBOX_TYPES.WEB) {
    return installationLimit.value;
  }

  const channelLimit = getMaxUploadSizeByChannel({
    channelType,
    medium: activeInbox.value?.medium,
    mime,
  });

  if (channelLimit === DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
    return installationLimit.value;
  }

  return Math.min(channelLimit, installationLimit.value);
};

const alertOverLimit = maxSizeMB =>
  useAlert(
    t('CONVERSATION.FILE_SIZE_LIMIT', {
      MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
    })
  );

const attachFile = ({ blob, file }) => {
  if (!file) return;
  const fileToRead = file?.file || file;
  if (!(fileToRead instanceof Blob)) return;

  const reader = new FileReader();
  reader.readAsDataURL(fileToRead);
  reader.onloadend = () => {
    const newFile = {
      resource: blob || fileToRead,
      isPrivate: false,
      thumb: reader.result,
      blobSignedId: blob?.signed_id,
    };
    attachedFiles.value = [...attachedFiles.value, newFile];
  };
};

const mapExistingAttachment = attachment => {
  const signedId = attachment.blobSignedId || attachment.blob_signed_id;
  const filename = attachment.filename || attachment.name || 'attachment';
  const dataUrl = attachment.url || attachment.data_url || '';

  return {
    resource: {
      id: attachment.id || signedId || filename,
      signed_id: signedId,
      blob_signed_id: signedId,
      filename,
      name: filename,
      content_type: attachment.contentType || attachment.content_type || '',
      contentType: attachment.contentType || attachment.content_type || '',
      type: attachment.contentType || attachment.content_type || '',
      byte_size: attachment.byteSize || attachment.byte_size || 0,
      data_url: dataUrl,
    },
    thumb: attachment.thumbUrl || attachment.thumb_url || dataUrl,
    blobSignedId: signedId,
  };
};

const handleFileUpload = (file, oldFile) => {
  if (!file || oldFile) return;
  const nativeFile = file.file || file;
  if (!(nativeFile instanceof File)) return;

  if (!activeConversationId.value) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_REQUIRED'));
    return;
  }

  const mime = nativeFile.type || file.type;
  const maxSizeMB = maxSizeFor(mime);

  if (!checkFileSizeLimit(file, maxSizeMB)) {
    alertOverLimit(maxSizeMB);
    return;
  }

  if (directUploadsEnabled.value) {
    uploadCount.value += 1;
    let upload;
    try {
      upload = new DirectUpload(
        nativeFile,
        `/api/v1/accounts/${accountId.value}/conversations/${activeConversationId.value}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            xhr.setRequestHeader(
              'api_access_token',
              currentUser.value?.access_token
            );
          },
        }
      );
    } catch (error) {
      uploadCount.value -= 1;
      useAlert(
        error?.message || t('KANBAN.SCHEDULED_MESSAGES.SAVE_ERROR')
      );
      return;
    }

    upload.create((error, blob) => {
      uploadCount.value -= 1;
      if (error) {
        useAlert(error);
        return;
      }
      attachFile({ blob, file });
    });
  } else {
    attachFile({ file });
  }
};

const prepareAttachmentsPayload = () => {
  if (!attachedFiles.value.length) return [];
  return attachedFiles.value
    .map(attachment => {
      const existingSignedId =
        attachment.blobSignedId ??
        attachment.blob_signed_id ??
        attachment.resource?.signed_id ??
        attachment.resource?.blob_signed_id;

      if (existingSignedId) {
        return existingSignedId;
      }

      if (directUploadsEnabled.value) {
        const id =
          attachment.blobSignedId ??
          attachment.blob_signed_id ??
          attachment.resource?.signed_id;
        return id || null;
      }
      if (attachment.resource?.file) return attachment.resource.file;
      if (attachment.file) return attachment.file;
      if (attachment.resource instanceof File) return attachment.resource;
      return null;
    })
    .filter(Boolean);
};

// Buscar contatos usando ContactAPI.search (mesma lógica da página de contatos)
const searchContacts = debounce(async (query) => {
  if (!query || !query.trim()) {
    searchResults.value = [];
    isSearching.value = false;
    return;
  }

  isSearching.value = true;
  try {
    const { data: { payload } } = await ContactAPI.search(
      encodeURIComponent(query.trim()),
      1,
      'name',
      ''
    );
    searchResults.value = payload || [];
  } catch (error) {
    console.error('Erro ao buscar contatos:', error);
    searchResults.value = [];
  } finally {
    isSearching.value = false;
  }
}, 300);

// Buscar conversas do contato selecionado
const fetchContactConversations = async (contactId) => {
  isFetchingConversations.value = true;
  try {
    const { data: { payload } } = await ContactAPI.getConversations(contactId);
    const conversations = payload || [];
    
    // Ordenar conversas por data de criação/atualização (mais recente primeiro)
    const sortedConversations = conversations.sort((a, b) => {
      // Lidar com timestamps (inteiros) ou strings de data
      const getTimestamp = (date) => {
        if (!date) return 0;
        if (typeof date === 'number') return date;
        return new Date(date).getTime() || 0;
      };
      
      const timestampA = getTimestamp(a.last_activity_at || a.created_at);
      const timestampB = getTimestamp(b.last_activity_at || b.created_at);
      return timestampB - timestampA; // Mais recente primeiro
    });
    
    contactConversations.value = sortedConversations;
    
    // Se houver conversas, usar a mais recente automaticamente
    if (sortedConversations.length > 0) {
      const mostRecentConversation = sortedConversations[0];
      selectedConversation.value = mostRecentConversation;
      formData.value.conversationId = mostRecentConversation.id;
      formData.value.inboxId = mostRecentConversation.inbox_id || formData.value.inboxId;
    } else {
      // Se não houver conversas, buscar inboxes do contato
      try {
        const { data: { payload: inboxesData } } = await ContactAPI.getContactableInboxes(contactId);
        if (inboxesData && inboxesData.length > 0) {
          // Usar o primeiro inbox disponível
          formData.value.inboxId = inboxesData[0].inbox?.id || inboxesData[0].id;
        }
      } catch (error) {
        console.error('Erro ao buscar inboxes do contato:', error);
      }
    }
  } catch (error) {
    console.error('Erro ao buscar conversas do contato:', error);
    contactConversations.value = [];
  } finally {
    isFetchingConversations.value = false;
  }
};

// Selecionar contato
const selectContact = async (contact) => {
  selectedContact.value = contact;
  formData.value.contactId = contact.id;
  searchQuery.value = '';
  searchResults.value = [];
  attachedFiles.value = [];
  
  // Buscar conversas do contato (vai selecionar automaticamente a mais recente)
  await fetchContactConversations(contact.id);
};

// Função removida - conversa mais recente é selecionada automaticamente

// Limpar seleção de contato
const clearContactSelection = () => {
  selectedContact.value = null;
  selectedConversation.value = null;
  formData.value.contactId = null;
  formData.value.conversationId = null;
  contactConversations.value = [];
  attachedFiles.value = [];
};

const dialogRef = ref(null);

const getContactName = (contact) =>
  contact?.name || contact?.identifier || contact?.email || 'Sem nome';

const getContactPhone = (contact) =>
  contact?.phone_number ||
  contact?.phoneNumber ||
  contact?.identifier ||
  contact?.email ||
  '';

const getContactAvatar = (contact) =>
  contact?.thumbnail || contact?.avatar_url || contact?.avatar || '';

// Funções helper para timezone
// Converter data local (datetime-local format) para UTC
const localToUTC = (localDateString) => {
  // localDateString está no formato "YYYY-MM-DDTHH:mm" (sem timezone)
  // O input datetime-local sempre retorna valores no timezone local do navegador
  // IMPORTANTE: datetime-local não inclui timezone, então precisamos criar Date no timezone local
  
  // Tentar criar Date diretamente primeiro (funciona na maioria dos casos)
  let localDate = new Date(localDateString);
  
  // Se a data for inválida ou se o parse não funcionou corretamente, fazer parse manual
  if (isNaN(localDate.getTime())) {
    const [datePart, timePart] = localDateString.split('T');
    const [year, month, day] = datePart.split('-').map(Number);
    const [hours, minutes] = timePart.split(':').map(Number);
    
    // Criar Date no timezone local usando construtor local
    // new Date(year, month, day, hours, minutes) cria uma data no timezone local do navegador
    localDate = new Date(year, month - 1, day, hours, minutes);
  }
  
  // Verificar se a data é válida
  if (isNaN(localDate.getTime())) {
    console.error('ScheduledMessageForm - Data inválida:', localDateString);
    throw new Error('Data/hora inválida');
  }
  
  // Retornar ISO string (que já está em UTC)
  // toISOString() converte automaticamente de local para UTC
  return localDate.toISOString();
};

// Converter UTC para local (para exibição em datetime-local)
const utcToLocal = (utcDateString) => {
  // Parse da string UTC (ISO 8601)
  const utcDate = new Date(utcDateString);
  
  // Formatar para datetime-local (YYYY-MM-DDTHH:mm) no timezone local
  const year = utcDate.getFullYear();
  const month = String(utcDate.getMonth() + 1).padStart(2, '0');
  const day = String(utcDate.getDate()).padStart(2, '0');
  const hours = String(utcDate.getHours()).padStart(2, '0');
  const minutes = String(utcDate.getMinutes()).padStart(2, '0');
  
  return `${year}-${month}-${day}T${hours}:${minutes}`;
};

watch(
  () => props.show,
  (newShow) => {
    if (newShow) {
      let defaultDate = new Date();
      const now = new Date();

      const normalizeDate = value => {
        if (!value) return null;
        if (value instanceof Date) return new Date(value);
        if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
          const [year, month, day] = value.split('-').map(Number);
          return new Date(year, month - 1, day);
        }
        return new Date(value);
      };

      const applyCurrentTimeIfMissing = date => {
        if (!date) return date;
        const isMidnight =
          date.getHours() === 0 &&
          date.getMinutes() === 0 &&
          date.getSeconds() === 0 &&
          date.getMilliseconds() === 0;

        if (isMidnight) {
          date.setHours(now.getHours(), now.getMinutes(), 0, 0);
        }
        return date;
      };

      const scheduledDateValue =
        props.scheduledMessage?.scheduledAt || props.scheduledMessage?.scheduled_at;

      if (isEditMode.value && scheduledDateValue) {
        defaultDate = normalizeDate(scheduledDateValue);
      } else if (props.selectedDate) {
        defaultDate = normalizeDate(props.selectedDate);
      } else if (props.conversation?.date) {
        defaultDate = normalizeDate(props.conversation.date);
      }

      defaultDate = applyCurrentTimeIfMissing(defaultDate || new Date());

      const year = defaultDate.getFullYear();
      const month = String(defaultDate.getMonth() + 1).padStart(2, '0');
      const day = String(defaultDate.getDate()).padStart(2, '0');
      const hours = String(defaultDate.getHours()).padStart(2, '0');
      const minutes = String(defaultDate.getMinutes()).padStart(2, '0');
      const formattedDate = `${year}-${month}-${day}T${hours}:${minutes}`;

      const scheduledMessage = props.scheduledMessage || {};
      const defaultInboxId =
        scheduledMessage.inboxId ||
        scheduledMessage.inbox_id ||
        props.conversation?.inboxId ||
        props.conversation?.inbox_id ||
        (inboxes.value.length > 0 ? inboxes.value[0].id : null);

      const conversationId =
        scheduledMessage.conversationId ||
        scheduledMessage.conversation_id ||
        props.conversation?.id ||
        null;

      formData.value = {
        message: isEditMode.value
          ? (scheduledMessage.message || '').toString()
          : '',
        scheduledAt: isEditMode.value && (scheduledMessage.scheduledAt || scheduledMessage.scheduled_at)
          ? utcToLocal(scheduledMessage.scheduledAt || scheduledMessage.scheduled_at)
          : formattedDate,
        inboxId: defaultInboxId,
        conversationId,
        contactId: null,
      };
      
      // Resetar estados de busca
      uploadCount.value = 0;
      searchQuery.value = '';
      searchResults.value = [];
      selectedContact.value = null;
      selectedConversation.value = null;
      contactConversations.value = [];
      attachedFiles.value = isEditMode.value
        ? Array(scheduledMessage.attachments || []).map(mapExistingAttachment)
        : [];
      
      nextTick(() => {
        setTimeout(() => {
          if (dialogRef.value && typeof dialogRef.value.open === 'function') {
            dialogRef.value.open();
          }
        }, 10);
      });
    } else {
      uploadCount.value = 0;
      if (dialogRef.value && typeof dialogRef.value.close === 'function') {
        dialogRef.value.close();
      }
    }
  },
  { immediate: true }
);

watch(searchQuery, (newQuery) => {
  if (newQuery && newQuery.trim()) {
    searchContacts(newQuery);
  } else {
    searchResults.value = [];
    isSearching.value = false;
  }
});

onMounted(async () => {
  await store.dispatch('kanban/fetchWahaInboxes');
  if (props.show) {
    nextTick(() => {
      setTimeout(() => {
        if (dialogRef.value && typeof dialogRef.value.open === 'function') {
          dialogRef.value.open();
        }
      }, 10);
    });
  }
});

const save = async () => {
  if (isUploadingAttachments.value) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_UPLOADING'));
    return;
  }

  if (isEditMode.value && props.scheduledMessage?.status !== 'pending') {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.ONLY_PENDING_EDIT'));
    return;
  }

  const hasText = (formData.value.message || '').trim().length > 0;
  const hasAttachments = attachedFiles.value.length > 0;
  if (!hasText && !hasAttachments) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_REQUIRED'));
    return;
  }

  if (!formData.value.scheduledAt) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_REQUIRED'));
    return;
  }

  const inputDate = formData.value.scheduledAt;
  let scheduledAtUTC;
  try {
    scheduledAtUTC = localToUTC(inputDate);
  } catch (error) {
    console.error('Erro ao converter data:', error);
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_INVALID'));
    return;
  }

  const utcDate = new Date(scheduledAtUTC);
  const nowUTC = new Date();

  if (utcDate <= nowUTC) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.DATE_FUTURE'));
    return;
  }

  const conversationId =
    props.conversation?.id ||
    formData.value.conversationId ||
    props.scheduledMessage?.conversationId ||
    props.scheduledMessage?.conversation_id;

  if (props.requireConversation && (!props.conversation || !props.conversation.id)) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_REQUIRED'));
    return;
  }

  if (!isEditMode.value && !props.requireConversation && !selectedContact.value) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONTACT_REQUIRED'));
    return;
  }

  if (!conversationId) {
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_REQUIRED'));
    return;
  }

  try {
    const attachmentsPayload = prepareAttachmentsPayload();
    const hasSelectedAttachments = attachedFiles.value.length > 0;
    const hasAttachmentPayload = attachmentsPayload.length > 0;

    if (!isEditMode.value && hasSelectedAttachments && !hasAttachmentPayload) {
      useAlert(t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_UPLOADING') || 'Aguarde o upload dos anexos terminar.');
      return;
    }

    const hasFileAttachments =
      attachmentsPayload.length > 0 &&
      attachmentsPayload.some(a => a instanceof File);

    const messagePayload = {
      message: (formData.value.message || '').trim(),
      scheduled_at: scheduledAtUTC,
    };

    if (!isEditMode.value) {
      messagePayload.conversation_id = conversationId;
    }

    if (formData.value.inboxId) {
      messagePayload.inbox_id = formData.value.inboxId;
    }

    const shouldSendAttachments = !isEditMode.value
      ? hasAttachmentPayload
      : !hasSelectedAttachments || hasAttachmentPayload;

    let payload;
    if (hasFileAttachments) {
      const formDataPayload = new FormData();
      Object.entries(messagePayload).forEach(([key, value]) => {
        if (value == null) return;
        formDataPayload.append(`scheduled_message[${key}]`, value);
      });
      if (shouldSendAttachments) {
        attachmentsPayload.forEach(attachment => {
          if (attachment instanceof File || typeof attachment === 'string') {
            formDataPayload.append(
              'scheduled_message[attachments][]',
              attachment
            );
          }
        });
      }
      payload = formDataPayload;
    } else {
      if (shouldSendAttachments) {
        messagePayload.attachments = attachmentsPayload;
      }

      payload = isEditMode.value
        ? messagePayload
        : { scheduled_message: messagePayload };
    }

    if (isEditMode.value) {
      await store.dispatch('kanban/updateScheduledMessage', {
        messageId: props.scheduledMessage.id,
        data: payload,
      });
    } else {
      await store.dispatch('kanban/createScheduledMessage', payload);
    }

    emit('saved');
    emit('close');
  } catch (error) {
    console.error('Erro ao salvar mensagem agendada:', error);
    useAlert(t('KANBAN.SCHEDULED_MESSAGES.SAVE_ERROR'));
  }
};

const close = () => {
  emit('close');
};
</script>

<template>
  <Dialog
    v-if="show"
    ref="dialogRef"
    :title="dialogTitle"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
    width="xl"
    @close="() => emit('close')"
  >
    <div class="space-y-5">
      <!-- Informações do Contato (quando há conversation ou contato selecionado) -->
      <div v-if="contactInfo" class="p-4 bg-n-solid-3 rounded-lg border border-n-weak">
        <div class="flex items-center gap-3">
          <Avatar
            :src="contactInfo.avatar || ''"
            :name="contactInfo.name || 'Sem nome'"
            :size="48"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-n-slate-12 truncate">
              {{ contactInfo.name }}
            </p>
            <p class="text-xs text-n-slate-10 font-mono">
              {{ contactInfo.phone }}
            </p>
          </div>
        </div>
      </div>

      <!-- Seleção de Contato (quando não há conversation) -->
      <div v-if="showContactSelector" class="space-y-2">
        <label class="block text-sm font-semibold mb-2 text-n-slate-12">
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-user" class="size-4" />
            Contato
            <span class="text-xs text-n-slate-10 font-normal">(obrigatório)</span>
          </div>
        </label>
        
        <!-- Campo de busca de contatos -->
        <div v-if="!selectedContact" class="relative">
          <Input
            v-model="searchQuery"
            type="search"
            :placeholder="t('CONTACTS_LAYOUT.HEADER.SEARCH_PLACEHOLDER')"
            :custom-input-class="[
              'h-10 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 ltr:!pl-8 !py-1 rtl:!pr-8',
            ]"
            @input="() => {}"
            @focus="() => {}"
          >
            <template #prefix>
              <Icon
                icon="i-lucide-search"
                class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
              />
            </template>
          </Input>
        </div>

        <!-- Loading durante busca -->
        <div
          v-if="isSearching"
          class="flex items-center justify-center py-4 text-n-slate-11"
        >
          <Spinner />
          <span class="ml-2 text-sm">Buscando contatos...</span>
        </div>

        <!-- Lista de resultados de contatos -->
        <div
          v-if="!isSearching && searchResults.length > 0 && !selectedContact && searchQuery"
          class="max-h-60 overflow-y-auto border border-n-weak rounded-lg bg-n-solid-3"
      >
          <button
            v-for="contact in searchResults"
            :key="contact.id"
            type="button"
            class="w-full px-4 py-3 flex items-center gap-3 hover:bg-n-solid-4 transition-colors border-b border-n-weak last:border-b-0"
            @click="selectContact(contact)"
          >
            <Avatar
              :src="getContactAvatar(contact)"
              :name="getContactName(contact)"
              :size="40"
            />
            <div class="flex-1 min-w-0 text-left">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ getContactName(contact) }}
              </p>
              <p class="text-xs text-n-slate-10 font-mono truncate">
                {{ getContactPhone(contact) }}
              </p>
            </div>
          </button>
        </div>

        <!-- Mensagem quando não há resultados -->
        <div
          v-if="!isSearching && searchQuery && searchResults.length === 0 && !selectedContact"
          class="p-4 text-center text-sm text-n-slate-10"
        >
          Nenhum contato encontrado
        </div>

        <!-- Contato selecionado -->
        <div
          v-if="selectedContact"
          class="p-3 bg-n-blue-3 border border-n-blue-9 rounded-lg flex items-center justify-between"
        >
          <div class="flex items-center gap-3">
            <Avatar
              :src="getContactAvatar(selectedContact)"
              :name="getContactName(selectedContact)"
              :size="40"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-blue-12 truncate">
                {{ getContactName(selectedContact) }}
              </p>
              <p class="text-xs text-n-blue-10 font-mono truncate">
                {{ getContactPhone(selectedContact) }}
          </p>
            </div>
          </div>
          <button
            type="button"
            class="text-n-blue-11 hover:text-n-blue-12 ml-2"
            @click="clearContactSelection"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>

        <!-- Loading ao buscar conversas -->
        <div
          v-if="isFetchingConversations"
          class="flex items-center justify-center py-4 text-n-slate-11"
        >
          <Spinner />
          <span class="ml-2 text-sm">Buscando conversas...</span>
        </div>

        <!-- Mensagem quando contato não tem conversas -->
        <div
          v-if="selectedContact && !isFetchingConversations && contactConversations.length === 0"
          class="p-4 bg-n-slate-3 border border-n-weak rounded-lg text-sm text-n-slate-11"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-info" class="size-4 text-n-slate-10" />
            <span>Este contato não possui conversas. Por favor, selecione um inbox e crie uma conversa primeiro através do sistema normal.</span>
          </div>
        </div>
      </div>

      <!-- Form Fields -->
      <div class="space-y-5">
        <!-- Inbox Selection (opcional - usa inbox da conversa se não selecionado) -->
        <div v-if="inboxes.length > 0">
          <label class="block text-sm font-semibold mb-2 text-n-slate-12">
            <div class="flex items-center gap-2">
              <Icon icon="i-lucide-inbox" class="size-4" />
              {{ t('KANBAN.SCHEDULED_MESSAGES.INBOX') }}
              <span class="text-xs text-n-slate-10 font-normal">(opcional)</span>
            </div>
          </label>
          <select
            v-model="formData.inboxId"
            class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
          >
            <option :value="null">Usar inbox da conversa</option>
            <option
              v-for="inbox in inboxes"
              :key="inbox.id"
              :value="inbox.id"
            >
              {{ inbox.name }}
            </option>
          </select>
        </div>

        <!-- Message -->
        <div>
          <label class="block text-sm font-semibold mb-2 text-n-slate-12">
            <div class="flex items-center gap-2">
              <Icon icon="i-lucide-message-square" class="size-4" />
              {{ t('KANBAN.SCHEDULED_MESSAGES.MESSAGE') }}
            </div>
          </label>
          <textarea
            v-model="formData.message"
            rows="5"
            class="w-full px-4 !py-3 !h-auto border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-blue-9 resize-none"
            :placeholder="t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_PLACEHOLDER')"
          />
          <p class="text-xs text-n-slate-10 mt-1">
            {{ formData.message.length }} {{ t('KANBAN.SCHEDULED_MESSAGES.CHARACTERS') }}
          </p>
        </div>

        <!-- Attachments -->
        <div>
          <label class="block text-sm font-semibold mb-2 text-n-slate-12">
            <div class="flex items-center gap-2">
              <Icon icon="i-lucide-paperclip" class="size-4" />
              {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS') }}
              <span class="text-xs text-n-slate-10 font-normal">(opcional)</span>
            </div>
          </label>
          <div class="flex items-center gap-3">
            <FileUpload
              input-id="scheduledMessageAttachment"
              :size="4096 * 4096"
              :accept="ALLOWED_FILE_TYPES"
              multiple
              :drop-directory="false"
              :disabled="!activeConversationId"
              :data="{
                direct_upload_url: '/rails/active_storage/direct_uploads',
                direct_upload: true,
              }"
              class="p-px"
              @input-file="handleFileUpload"
            >
              <Button
                icon="i-lucide-plus"
                color="slate"
                size="sm"
                class="!w-10"
                :disabled="!activeConversationId"
              />
            </FileUpload>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">
                <span v-if="attachedFiles.length > 0">
                  {{
                    t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_SELECTED', {
                      count: attachedFiles.length,
                    })
                  }}
                </span>
                <span v-else>
                  {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACH_FILE') }}
                </span>
              </span>
              <span
                v-if="isUploadingAttachments"
                class="text-xs text-n-slate-10 flex items-center gap-1"
              >
                <Spinner class="!size-3" />
                {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_UPLOADING') }}
              </span>
            </div>
          </div>
          <p
            v-if="!activeConversationId"
            class="text-xs text-n-slate-10 mt-2"
          >
            {{ t('KANBAN.SCHEDULED_MESSAGES.ATTACHMENTS_REQUIRED') }}
          </p>
          <AttachmentPreviews
            v-if="attachedFiles.length > 0"
            :attachments="attachedFiles"
            @update:attachments="attachedFiles = $event"
          />
        </div>

        <!-- Date and Time -->
        <div>
          <label class="block text-sm font-semibold mb-2 text-n-slate-12">
            <div class="flex items-center gap-2">
              <Icon icon="i-lucide-calendar-clock" class="size-4" />
              {{ t('KANBAN.SCHEDULED_MESSAGES.SCHEDULED_AT') }}
            </div>
          </label>
          <input
            v-model="formData.scheduledAt"
            type="datetime-local"
            class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
          />
        </div>

        <!-- Preview -->
        <div v-if="formData.message" class="p-4 bg-n-solid-3 rounded-lg border border-n-weak">
          <p class="text-xs font-semibold text-n-slate-11 mb-2 flex items-center gap-2">
            <Icon icon="i-lucide-eye" class="size-4" />
            {{ t('KANBAN.SCHEDULED_MESSAGES.PREVIEW') }}
          </p>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ formData.message }}
          </p>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="button"
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="close"
        />
        <Button
          :label="submitButtonLabel"
          color="blue"
          type="button"
          :is-loading="isLoading || isUploadingAttachments"
          :disabled="isUploadingAttachments"
          @click="save"
        />
      </div>
    </template>
  </Dialog>
</template>
