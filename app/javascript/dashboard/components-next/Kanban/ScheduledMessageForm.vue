<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components/widgets/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactAPI from 'dashboard/api/contacts';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversation: {
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
// Removido - não precisamos mais mostrar lista de conversas

const inboxes = computed(() => store.getters['kanban/getWahaInboxes']);
const isLoading = computed(() => store.getters['kanban/getUIFlags'].isCreating);

const showContactSelector = computed(() => {
  return !props.requireConversation && !props.conversation;
});

// Informações do contato quando há conversation
const contactInfo = computed(() => {
  if (props.conversation) {
    const contact = props.conversation.contact;
    return {
      name: contact?.name || 'Sem nome',
      phone: contact?.phone_number || contact?.phoneNumber || '',
      avatar: contact?.thumbnail || contact?.avatar_url || contact?.avatar || '',
    };
  }
  if (selectedContact.value) {
    return {
      name: selectedContact.value.name || 'Sem nome',
      phone: selectedContact.value.phone_number || selectedContact.value.phoneNumber || '',
      avatar: selectedContact.value.thumbnail || '',
    };
  }
  return null;
});

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
};

const dialogRef = ref(null);

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
      // Usar data selecionada ou data padrão
      let defaultDate;
      
      if (props.selectedDate) {
        // Se selectedDate for uma string ISO (UTC), converter para local
        if (typeof props.selectedDate === 'string' && props.selectedDate.includes('T') && props.selectedDate.includes('Z')) {
          defaultDate = new Date(props.selectedDate);
        } else {
          defaultDate = new Date(props.selectedDate);
        }
      } else if (props.conversation?.date) {
        // Se conversation.date for uma string ISO (UTC), converter para local
        if (typeof props.conversation.date === 'string' && props.conversation.date.includes('T') && props.conversation.date.includes('Z')) {
          defaultDate = new Date(props.conversation.date);
        } else {
          defaultDate = new Date(props.conversation.date);
        }
      } else {
        // Usar data/hora atual no timezone local
        defaultDate = new Date();
      }
      
      if (!props.selectedDate && !props.conversation?.date) {
        // Adicionar 1 hora à data atual
        defaultDate.setHours(defaultDate.getHours() + 1);
      }
      
      // Formatar para datetime-local (YYYY-MM-DDTHH:mm) no timezone local
      // IMPORTANTE: Os métodos getFullYear(), getMonth(), getDate(), getHours(), getMinutes()
      // já retornam valores no timezone local do navegador automaticamente
      // Não precisamos fazer nenhuma conversão aqui - o JavaScript já faz isso
      const year = defaultDate.getFullYear();
      const month = String(defaultDate.getMonth() + 1).padStart(2, '0');
      const day = String(defaultDate.getDate()).padStart(2, '0');
      const hours = String(defaultDate.getHours()).padStart(2, '0');
      const minutes = String(defaultDate.getMinutes()).padStart(2, '0');
      const formattedDate = `${year}-${month}-${day}T${hours}:${minutes}`;
      
      // Debug: verificar timezone
      console.log('ScheduledMessageForm - Data formatada:', {
        formattedDate,
        localHours: defaultDate.getHours(),
        localMinutes: defaultDate.getMinutes(),
        utcHours: defaultDate.getUTCHours(),
        utcMinutes: defaultDate.getUTCMinutes(),
        timezoneOffset: defaultDate.getTimezoneOffset(),
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        now: new Date().toISOString(),
        nowLocal: new Date().toLocaleString()
      });
      
      // Usar o inbox da conversa como padrão se disponível
      const defaultInboxId = props.conversation?.inboxId || props.conversation?.inbox_id || 
                            (inboxes.value.length > 0 ? inboxes.value[0].id : null);
      
      formData.value = {
        message: '',
        scheduledAt: formattedDate,
        inboxId: defaultInboxId,
        conversationId: props.conversation?.id || null,
        contactId: null,
      };
      
      // Resetar estados de busca
      searchQuery.value = '';
      searchResults.value = [];
      selectedContact.value = null;
      selectedConversation.value = null;
      contactConversations.value = [];
      
      nextTick(() => {
        setTimeout(() => {
          if (dialogRef.value && typeof dialogRef.value.open === 'function') {
            dialogRef.value.open();
          }
        }, 10);
      });
    } else {
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
  if (!formData.value.message.trim()) {
    alert(t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_REQUIRED'));
    return;
  }

  if (!formData.value.scheduledAt) {
    alert(t('KANBAN.SCHEDULED_MESSAGES.DATE_REQUIRED'));
    return;
  }

  // Converter data/hora do input (datetime-local retorna sem timezone)
  // O input retorna "YYYY-MM-DDTHH:mm" no timezone local do navegador
  // Converter para UTC usando a função helper
  const inputDate = formData.value.scheduledAt; // Formato: "YYYY-MM-DDTHH:mm"
  
  console.log('ScheduledMessageForm - Convertendo data:', {
    inputDate,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    timezoneOffset: new Date().getTimezoneOffset()
  });
  
  // Converter de local para UTC
  let scheduledAtUTC;
  try {
    scheduledAtUTC = localToUTC(inputDate);
    console.log('ScheduledMessageForm - Data convertida para UTC:', scheduledAtUTC);
  } catch (error) {
    console.error('ScheduledMessageForm - Erro ao converter data:', error);
    alert('Erro ao processar data/hora. Por favor, verifique o formato.');
    return;
  }
  
  // Validar que a data está no futuro
  // Comparar em UTC para garantir precisão
  const utcDate = new Date(scheduledAtUTC);
  const nowUTC = new Date();
  
  console.log('ScheduledMessageForm - Validação de data:', {
    scheduledAtUTC,
    utcDate: utcDate.toISOString(),
    nowUTC: nowUTC.toISOString(),
    isFuture: utcDate > nowUTC
  });
  
  if (utcDate <= nowUTC) {
    alert(t('KANBAN.SCHEDULED_MESSAGES.DATE_FUTURE'));
    return;
  }

  // Verificar se há conversation válida (se requireConversation for true)
  if (props.requireConversation && (!props.conversation || !props.conversation.id)) {
    alert(t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_REQUIRED'));
    return;
  }

  // Se não requireConversation, validar que contato foi selecionado
  if (!props.requireConversation && !selectedContact.value) {
    alert('Por favor, selecione um contato');
    return;
  }

  // Se não requireConversation, validar que há conversationId
  if (!props.requireConversation && !formData.value.conversationId) {
    alert('Por favor, selecione uma conversa do contato');
    return;
  }

  try {
    const payload = {
      scheduled_message: {
        conversation_id: props.conversation?.id || formData.value.conversationId,
      message: formData.value.message,
        scheduled_at: scheduledAtUTC,
      }
    };
    
    // Incluir inbox_id apenas se fornecido
    if (formData.value.inboxId) {
      payload.scheduled_message.inbox_id = formData.value.inboxId;
    }
    
    await store.dispatch('kanban/createScheduledMessage', payload);

    emit('saved');
    emit('close');
  } catch (error) {
    console.error('Erro ao agendar mensagem:', error);
    alert(t('KANBAN.SCHEDULED_MESSAGES.SAVE_ERROR'));
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
    :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
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
              :src="contact.thumbnail || ''"
              :name="contact.name || 'Sem nome'"
              :size="40"
            />
            <div class="flex-1 min-w-0 text-left">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ contact.name || 'Sem nome' }}
              </p>
              <p class="text-xs text-n-slate-10 font-mono truncate">
                {{ contact.phone_number || contact.phoneNumber || '' }}
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
              :src="selectedContact.thumbnail || ''"
              :name="selectedContact.name || 'Sem nome'"
              :size="40"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-blue-12 truncate">
                {{ selectedContact.name || 'Sem nome' }}
              </p>
              <p class="text-xs text-n-blue-10 font-mono truncate">
                {{ selectedContact.phone_number || selectedContact.phoneNumber || '' }}
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

        <!-- Informação da conversa selecionada (quando contato foi selecionado) -->
        <div v-if="selectedContact && selectedConversation" class="p-3 bg-n-blue-3 border border-n-blue-9 rounded-lg">
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-check-circle" class="size-4 text-n-blue-9" />
            <span class="text-sm text-n-blue-12">
              Usando conversa mais recente #{{ selectedConversation.id }}
            </span>
          </div>
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
            class="w-full px-4 py-3 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
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
            class="w-full px-4 py-3 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-9 resize-none"
            :placeholder="t('KANBAN.SCHEDULED_MESSAGES.MESSAGE_PLACEHOLDER')"
          />
          <p class="text-xs text-n-slate-10 mt-1">
            {{ formData.message.length }} {{ t('KANBAN.SCHEDULED_MESSAGES.CHARACTERS') }}
          </p>
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
            class="w-full px-4 py-3 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-9"
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
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="close"
        />
        <Button
          :label="t('KANBAN.SCHEDULED_MESSAGES.SCHEDULE')"
          color="blue"
          :is-loading="isLoading"
          @click="save"
        />
      </div>
    </template>
  </Dialog>
</template>
