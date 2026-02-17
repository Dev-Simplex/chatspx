<script setup>
import { computed, onMounted, watch, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['schedule-message', 'remove-item', 'manage-scheduled']);

const store = useStore();
const router = useRouter();
const { t } = useI18n();

// Filtros
const searchQuery = ref('');
const selectedStageId = ref(null);
const selectedLabelId = ref(null);
const selectedAssigneeId = ref(null);

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);

const allItems = computed(() => {
  const items = [];
  stages.value.forEach(stage => {
    const stageItems = store.getters['kanban/getFunnelItems'](
      props.funnelId,
      stage.id
    );
    stageItems.forEach(item => {
      items.push({
        ...item,
        stageId: stage.id,
        stageName: stage.name,
        stageColor: stage.color,
      });
    });
  });
  return items;
});

const conversations = computed(() => {
  const items = allItems.value;
  const conversationMap = {};
  
  items.forEach(item => {
    if (item.conversationId && !conversationMap[item.conversationId]) {
      const getConversationById = store.getters['conversations/getConversationById'];
      if (getConversationById) {
        const conversation = getConversationById(item.conversationId);
        if (conversation && conversation.id) {
          // Função auxiliar para extrair assigneeId
          const getAssigneeId = (conv) => {
            if (!conv) return null;
            return (
              conv.assigneeId ||
              conv.assignee_id ||
              conv.assignee?.id ||
              conv.meta?.assignee?.id ||
              conv.meta?.assignee_id ||
              null
            );
          };
          
          // Garantir que assigneeId está presente mesmo se vier do store
          conversationMap[item.conversationId] = {
            ...conversation,
            assigneeId: getAssigneeId(conversation) || getAssigneeId(item.conversation),
          };
        } else {
          // Função auxiliar para extrair assigneeId
          const getAssigneeId = (conv) => {
            if (!conv) return null;
            return (
              conv.assigneeId ||
              conv.assignee_id ||
              conv.assignee?.id ||
              conv.meta?.assignee?.id ||
              conv.meta?.assignee_id ||
              null
            );
          };
          
          conversationMap[item.conversationId] = {
            id: item.conversationId,
            displayId: item.conversation?.displayId || item.conversation?.display_id || item.conversationId,
            status: 'open',
            contactId: item.conversation?.contactId || item.conversation?.contact_id,
            assigneeId: getAssigneeId(item.conversation),
          };
        }
      } else {
        conversationMap[item.conversationId] = {
          id: item.conversationId,
          displayId: item.conversation?.displayId || item.conversation?.display_id || item.conversationId,
          status: 'open',
          contactId: item.conversation?.contactId || item.conversation?.contact_id,
          assigneeId: item.conversation?.assigneeId || item.conversation?.assignee_id,
        };
      }
    }
  });
  
  return conversationMap;
});

const isLoading = computed(() => store.getters['kanban/getUIFlags'].isFetching);
const scheduledMessages = computed(() => store.getters['kanban/getScheduledMessages']);

// Estado de loading robusto que aguarda todos os dados
const isLoadingData = ref(true);

const getContactName = (conversationId) => {
  const conversation = conversations.value[conversationId];
  if (!conversation) {
    return t('KANBAN.ITEMS.UNNAMED_CONTACT');
  }
  
  // Tentar pegar o nome do contato de várias fontes
  const contactId = conversation.contactId || conversation.contact_id;
  
  if (!contactId) {
    // Se não tem contactId, tentar pegar do item diretamente
    const item = allItems.value.find(item => item.conversationId === conversationId);
    if (item?.conversation?.contact?.name) {
      return item.conversation.contact.name;
    }
    return t('KANBAN.ITEMS.UNNAMED_CONTACT');
  }
  
  try {
    const getContactById = store.getters['contacts/getContactById'];
    if (getContactById) {
      const contact = getContactById(contactId);
      if (contact && contact.name) {
        return contact.name;
      }
    }
    
    // Se não encontrou no store, tentar pegar do item
    const item = allItems.value.find(item => item.conversationId === conversationId);
    if (item?.conversation?.contact?.name) {
      return item.conversation.contact.name;
    }
    
    return t('KANBAN.ITEMS.UNNAMED_CONTACT');
  } catch (error) {
    console.error('Erro ao buscar contato:', error);
    return t('KANBAN.ITEMS.UNNAMED_CONTACT');
  }
};

const getContactPhone = (conversationId) => {
  const conversation = conversations.value[conversationId];
  if (!conversation || !conversation.contactId) {
    return '';
  }
  
  try {
    const getContactById = store.getters['contacts/getContactById'];
    if (getContactById) {
      const contact = getContactById(conversation.contactId);
      return contact?.phoneNumber || contact?.phone_number || '';
    }
    return '';
  } catch (error) {
    return '';
  }
};

const getContactAvatar = (conversationId) => {
  // 1. Tentar pegar do item diretamente primeiro (mais rápido)
  const item = allItems.value.find(item => item.conversationId === conversationId);
  if (item?.conversation?.contact) {
    const avatar = item.conversation.contact.thumbnail || 
                   item.conversation.contact.avatar_url || 
                   item.conversation.contact.avatar ||
                   item.conversation.contact.profile_image_url;
    if (avatar) {
      return avatar;
    }
  }
  
  // 2. Tentar pegar do conversationMap
  const conversation = conversations.value[conversationId];
  if (!conversation) {
    return '';
  }
  
  const contactId = conversation.contactId || conversation.contact_id;
  if (!contactId) {
    return '';
  }
  
  try {
    const getContactById = store.getters['contacts/getContactById'];
    if (getContactById) {
      const contact = getContactById(contactId);
      if (contact) {
        const avatar = contact.thumbnail ||
                       contact.avatar_url ||
                       contact.avatar ||
                       contact.profile_image_url;
        if (avatar) {
          return avatar;
        }
      } else {
        // Contato não está no store, tentar buscar
        // Fazer isso de forma assíncrona para não bloquear
        store.dispatch('contacts/get', contactId).catch(() => {
          // Ignorar erros
        });
      }
    }
    
    return '';
  } catch (error) {
    return '';
  }
};

const getConversationLabels = (conversationId) => {
  try {
    const getConversationLabels = store.getters['conversationLabels/getConversationLabels'];
    if (getConversationLabels) {
      return getConversationLabels(conversationId) || [];
    }
    return [];
  } catch (error) {
    return [];
  }
};

// Buscar todas as labels disponíveis na conta
const allLabels = computed(() => {
  try {
    // Buscar todas as labels da conta
    const accountLabels = store.getters['labels/getLabels'];
    if (Array.isArray(accountLabels) && accountLabels.length > 0) {
      // Ordenar por título
      return accountLabels
        .filter(label => label && label.id)
        .sort((a, b) => (a.title || '').localeCompare(b.title || ''));
    }
    
    // Fallback: se não tiver labels da conta, pegar das conversas
    const labelsSet = new Set();
    allItems.value.forEach(item => {
      const labels = getConversationLabels(item.conversationId);
      labels.forEach(label => {
        if (label && label.id) {
          labelsSet.add(JSON.stringify({ id: label.id, title: label.title, color: label.color }));
        }
      });
    });
    return Array.from(labelsSet).map(str => JSON.parse(str));
  } catch (error) {
    console.error('Erro ao buscar labels:', error);
    return [];
  }
});

// Buscar todos os agentes disponíveis
const allAgents = computed(() => {
  try {
    const agents = store.getters['agents/getAgents'];
    if (Array.isArray(agents) && agents.length > 0) {
      // Filtrar apenas agentes verificados e ordenar por nome
      return agents
        .filter(agent => agent && agent.id && agent.confirmed)
        .sort((a, b) => {
          const nameA = (a.name || a.email || '').toLowerCase();
          const nameB = (b.name || b.email || '').toLowerCase();
          return nameA.localeCompare(nameB);
        });
    }
    return [];
  } catch (error) {
    console.error('Erro ao buscar agentes:', error);
    return [];
  }
});

const getStatusTitle = (status) => {
  const statusMap = {
    open: t('KANBAN.STATUS.OPEN') || 'Aberto',
    pending: t('KANBAN.STATUS.PENDING') || 'Pendente',
    resolved: t('KANBAN.STATUS.RESOLVED') || 'Resolvido',
    snoozed: t('KANBAN.STATUS.SNOOZED') || 'Adiado',
  };
  return statusMap[status] || t('KANBAN.STATUS.OPEN') || 'Aberto';
};

const getStatusIcon = (status) => {
  const iconMap = {
    open: 'i-lucide-circle',
    pending: 'i-lucide-clock',
    resolved: 'i-lucide-check-circle',
    snoozed: 'i-lucide-moon',
  };
  return iconMap[status] || 'i-lucide-circle';
};

const getStatusColor = (status) => {
  const colorMap = {
    open: 'bg-green-500',
    pending: 'bg-yellow-500',
    resolved: 'bg-gray-500',
    snoozed: 'bg-blue-500',
  };
  return colorMap[status] || 'bg-gray-500';
};

const getPendingScheduledMessagesForConversation = conversationId => {
  return scheduledMessages.value
    .filter(message => {
      return (
        message.status === 'pending' &&
        Number(message.conversationId || message.conversation_id) === Number(conversationId)
      );
    })
    .sort((a, b) => new Date(a.scheduledAt) - new Date(b.scheduledAt));
};

const getPendingScheduledCount = conversationId =>
  getPendingScheduledMessagesForConversation(conversationId).length;

const getNextPendingScheduledAt = conversationId => {
  const [nextMessage] = getPendingScheduledMessagesForConversation(conversationId);
  return nextMessage?.scheduledAt || null;
};

const openScheduledManager = conversationId => {
  emit('manage-scheduled', conversationId);
};

// Filtrar itens
const filteredItems = computed(() => {
  let items = allItems.value;

  // Filtrar apenas conversas abertas (não resolvidas)
  items = items.filter(item => {
    const status = conversations.value[item.conversationId]?.status || 'open';
    return status !== 'resolved';
  });

  // Filtro por busca (nome ou telefone)
  if (searchQuery.value.trim()) {
    const query = searchQuery.value.toLowerCase().trim();
    items = items.filter(item => {
      const contactName = getContactName(item.conversationId).toLowerCase();
      const contactPhone = getContactPhone(item.conversationId).toLowerCase();
      const conversationNumber = String(conversations.value[item.conversationId]?.displayId || '').toLowerCase();
      return contactName.includes(query) || contactPhone.includes(query) || conversationNumber.includes(query);
    });
  }

  // Filtro por etapa
  if (selectedStageId.value) {
    items = items.filter(item => item.stageId === selectedStageId.value);
  }

  // Filtro por etiqueta
  if (selectedLabelId.value) {
    items = items.filter(item => {
      const labels = getConversationLabels(item.conversationId);
      return labels.some(label => label.id === selectedLabelId.value);
    });
  }

  // Filtro por agente atribuído
  if (selectedAssigneeId.value) {
    items = items.filter(item => {
      // Função auxiliar para extrair assigneeId de várias fontes
      const getAssigneeId = (obj) => {
        if (!obj) return null;
        
        // Tentar várias propriedades possíveis
        return (
          obj.assigneeId ||
          obj.assignee_id ||
          obj.assignee?.id ||
          obj.assignee?.user?.id ||
          obj.meta?.assignee?.id ||
          obj.meta?.assignee_id ||
          null
        );
      };
      
      // 1. Tentar pegar diretamente do item.conversation (vem da API com assignee_id)
      let assigneeId = item.conversation?.assignee_id || item.conversation?.assigneeId;
      
      // 2. Se não tiver, usar a função auxiliar para buscar em outras fontes
      if (!assigneeId) {
        assigneeId = getAssigneeId(item.conversation);
      }
      
      // 3. Se ainda não tiver, tentar pegar do conversationMap
      if (!assigneeId) {
        const conversation = conversations.value[item.conversationId];
        assigneeId = conversation?.assignee_id || conversation?.assigneeId || getAssigneeId(conversation);
      }
      
      // 4. Se ainda não tiver, tentar pegar do store
      if (!assigneeId) {
        const getConversationById = store.getters['conversations/getConversationById'];
        if (getConversationById) {
          const storeConversation = getConversationById(item.conversationId);
          assigneeId = storeConversation?.assignee_id || storeConversation?.assigneeId || getAssigneeId(storeConversation);
        }
      }
      
      
      // Comparar os IDs
      if (!assigneeId) {
        return false;
      }
      
      return Number(assigneeId) === Number(selectedAssigneeId.value);
    });
  }

  return items;
});

const openConversation = (item) => {
  const conversation = conversations.value[item.conversationId];
  const conversationId =
    conversation?.displayId ||
    conversation?.display_id ||
    conversation?.id ||
    item.conversation?.displayId ||
    item.conversation?.display_id ||
    item.conversation?.id ||
    item.conversationId ||
    item.conversation_id;
  
  if (conversationId) {
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
  }
};

const handleRemove = async (item) => {
  if (confirm(t('KANBAN.ITEMS.CONFIRM_REMOVE'))) {
    try {
      await store.dispatch('kanban/deleteItem', {
        funnelId: props.funnelId,
        itemId: item.id,
      });
      emit('remove-item', item);
    } catch (error) {
      console.error('Erro ao remover item:', error);
    }
  }
};

const clearFilters = () => {
  searchQuery.value = '';
  selectedStageId.value = null;
  selectedLabelId.value = null;
  selectedAssigneeId.value = null;
};

const hasActiveFilters = computed(() => {
  return searchQuery.value.trim() || selectedStageId.value || selectedLabelId.value || selectedAssigneeId.value;
});

const loadData = async () => {
  if (!props.funnelId) {
    isLoadingData.value = false;
    return;
  }
  
  isLoadingData.value = true;
  
  try {
    // 1. Carregar mensagens agendadas pendentes
    await store.dispatch('kanban/fetchScheduledMessages', { status: 'pending' });

    // 2. Carregar labels da conta (se ainda não estiverem carregadas)
    const accountLabels = store.getters['labels/getLabels'];
    if (!accountLabels || accountLabels.length === 0) {
      await store.dispatch('labels/get').catch(() => {
        // Ignorar erro se não conseguir carregar labels
      });
    }
    
    // 3. Carregar agentes (se ainda não estiverem carregados)
    const agents = store.getters['agents/getAgents'];
    if (!agents || agents.length === 0) {
      await store.dispatch('agents/get').catch(() => {
        // Ignorar erro se não conseguir carregar agentes
      });
    }
    
    // 4. Carregar etapas
  await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
    
    // 5. Carregar itens do funil (excluindo Resolvidos para performance)
  await store.dispatch('kanban/fetchFunnelItems', {
    funnelId: props.funnelId,
    excludeAutomationType: 'resolved',
  });
    
    // 6. Aguardar para garantir que os dados estão no store
    await new Promise(resolve => setTimeout(resolve, 200));
    
    // 7. Verificar e carregar contatos
    const items = allItems.value;
    const conversationIds = [...new Set(items.map(item => item.conversationId).filter(Boolean))];
    
    // Buscar conversas e verificar contatos com retry
    const getConversationById = store.getters['conversations/getConversationById'];
    const getContactById = store.getters['contacts/getContactById'];
    
    const contactIds = new Set();
    
    // Coletar todos os contactIds das conversas (do store E dos items)
    conversationIds.forEach(conversationId => {
      // Tentar pegar do store primeiro
      if (getConversationById) {
        const conversation = getConversationById(conversationId);
        if (conversation && (conversation.contactId || conversation.contact_id)) {
          contactIds.add(conversation.contactId || conversation.contact_id);
        }
      }
      
      // Também coletar dos items diretamente (fallback)
      const item = items.find(item => item.conversationId === conversationId);
      if (item?.conversation?.contactId || item?.conversation?.contact_id) {
        const contactId = item.conversation.contactId || item.conversation.contact_id;
        if (contactId) {
          contactIds.add(contactId);
        }
      }
    });
    
    // Buscar contatos que não estão no store
    const contactsToFetch = Array.from(contactIds).filter(contactId => {
      if (getContactById) {
        const contact = getContactById(contactId);
        // Verificar se o contato não existe OU não tem dados completos (nome ou avatar)
        return !contact || (!contact.name && !contact.thumbnail && !contact.avatar_url && !contact.avatar);
      }
      return true;
    });
    
    // Buscar contatos faltantes em paralelo
    if (contactsToFetch.length > 0) {
      const fetchPromises = contactsToFetch.map(contactId =>
        store.dispatch('contacts/get', contactId).catch(() => {
          // Ignorar erros individuais
        })
      );
      await Promise.all(fetchPromises);
    }
    
    // Aguardar um pouco para garantir que os dados foram atualizados no store
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verificar se contatos estão carregados, com retry
    let retries = 0;
    const maxRetries = 3;
    const retryDelay = 150;
    
    while (retries < maxRetries) {
      const missingContacts = Array.from(contactIds).filter(contactId => {
        // Se tem dados no item, considerar como OK
        const item = items.find(item => {
          const itemContactId = item.conversation?.contactId || item.conversation?.contact_id;
          return itemContactId === contactId && (item.conversation?.contact?.name || item.conversation?.contact?.thumbnail || item.conversation?.contact?.avatar_url);
        });
        if (item) {
          return false; // Tem dados no item, não precisa buscar
        }
        
        // Verificar se tem no store
        if (getContactById) {
          const contact = getContactById(contactId);
          return !contact || (!contact.name && !contact.thumbnail && !contact.avatar_url && !contact.avatar);
        }
        return true;
      });
      
      if (missingContacts.length === 0) {
        break; // Todos os contatos estão carregados
      }
      
      // Tentar buscar novamente os que estão faltando
      if (retries > 0 && missingContacts.length > 0) {
        const retryPromises = missingContacts.map(contactId =>
          store.dispatch('contacts/get', contactId).catch(() => {})
        );
        await Promise.all(retryPromises);
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      
      await new Promise(resolve => setTimeout(resolve, retryDelay));
      retries++;
    }
    
    // 8. Carregar labels das conversas apenas se a conversa existir no store
    // Verificar quais conversas realmente existem antes de tentar carregar labels
    const validConversationIds = conversationIds.filter(conversationId => {
      if (getConversationById) {
        const conversation = getConversationById(conversationId);
        return conversation && conversation.id;
      }
      return false;
    });
    
    // Carregar labels apenas para conversas válidas, em background
    if (validConversationIds.length > 0) {
      validConversationIds.forEach(conversationId => {
        // Carregar em background, ignorando erros 404
        store.dispatch('conversationLabels/get', conversationId).catch((error) => {
          // Ignorar erros 404 ou outros erros - muitas conversas não têm labels
          if (error.response?.status !== 404) {
            // Só logar se não for 404
            console.debug('Erro ao carregar labels para conversa', conversationId, error);
          }
        });
      });
    }
    
    // 9. Aguardar um pouco mais para garantir renderização
    await new Promise(resolve => setTimeout(resolve, 150));
    
    isLoadingData.value = false;
  } catch (error) {
    console.error('ListView: Erro ao carregar dados:', error);
    isLoadingData.value = false;
  }
};

onMounted(() => {
  loadData();
});

watch(
  () => props.funnelId,
  (newFunnelId, oldFunnelId) => {
    if (newFunnelId && newFunnelId !== oldFunnelId) {
      clearFilters();
      loadData();
    }
  }
);
</script>

<template>
  <div class="list-view-container h-full w-full flex flex-col bg-n-background">
    <!-- Loading State -->
    <div v-if="isLoading || isLoadingData" class="flex justify-center items-center h-full bg-n-background">
      <div class="flex flex-col items-center justify-center text-center max-w-sm">
        <div class="relative mb-6">
          <div class="size-16 rounded-full bg-n-teal-3 flex items-center justify-center">
            <Icon icon="i-lucide-loader-2" class="size-8 text-n-teal-9 animate-spin" />
          </div>
          <div class="absolute -inset-1 rounded-full bg-n-teal-6 opacity-20 animate-pulse"></div>
        </div>
        <h3 class="text-lg font-semibold text-n-slate-12 mb-2">{{ t('KANBAN.LOADING') }}</h3>
        <p class="text-sm text-n-slate-10 mb-1">Carregando conversas e contatos...</p>
        <div class="flex items-center gap-1.5 mt-4">
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0s"></div>
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.2s"></div>
          <div class="size-1.5 rounded-full bg-n-teal-9 animate-bounce" style="animation-delay: 0.4s"></div>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="allItems.length === 0"
      class="flex flex-col items-center justify-center h-full min-h-[400px] bg-gradient-to-br from-n-background via-n-solid-1 to-n-background"
    >
      <div class="mb-6 flex justify-center">
        <div class="relative">
          <div class="size-24 rounded-2xl bg-gradient-to-br from-n-teal-4 to-n-blue-4 flex items-center justify-center shadow-lg border-2 border-n-teal-6">
            <Icon icon="i-lucide-inbox" class="size-12 text-n-teal-9" />
          </div>
          <div class="absolute -top-2 -right-2 size-8 rounded-full bg-n-blue-5 border-2 border-n-background flex items-center justify-center">
            <Icon icon="i-lucide-message-square" class="size-4 text-n-blue-9" />
          </div>
        </div>
      </div>
      <h3 class="text-2xl font-bold text-n-slate-12 mb-2">{{ t('KANBAN.ITEMS.NO_ITEMS') }}</h3>
      <p class="text-base text-n-slate-11 mb-1">Não há conversas neste funil ainda</p>
      <p class="text-sm text-n-slate-10">As conversas aparecerão aqui quando forem adicionadas ao funil</p>
    </div>

    <!-- Content -->
    <div v-else class="flex flex-col h-full overflow-hidden">
      <!-- Header com Filtros -->
      <div class="flex-shrink-0 border-b border-n-weak bg-gradient-to-r from-n-solid-2 to-n-solid-3 p-4 shadow-sm">
        <div class="flex flex-col gap-4">
          <!-- Barra de Busca -->
          <div class="relative">
            <Icon
              icon="i-lucide-search"
              class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-9 pointer-events-none z-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Buscar por nome, telefone ou número da conversa..."
              class="w-full pl-10 pr-10 py-2.5 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-blue-9 focus:border-transparent"
            />
            <button
              v-if="searchQuery"
              @click="searchQuery = ''"
              class="absolute right-3 top-1/2 -translate-y-1/2 text-n-slate-9 hover:text-n-slate-11 z-10"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>

          <!-- Filtros -->
          <div class="flex flex-wrap items-center gap-3">
            <!-- Filtro por Etapa -->
            <div class="flex items-stretch gap-2">
              <div class="flex items-center justify-center" style="width: 16px; height: 42px;">
                <Icon icon="i-lucide-git-branch" class="size-4 text-n-slate-10" />
              </div>
              <div class="relative">
                <select
                  v-model="selectedStageId"
                  class="px-3 pr-8 py-2.5 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm focus:outline-none focus:ring-2 focus:ring-n-blue-9 min-w-[150px] appearance-none cursor-pointer"
                  style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none; height: 42px;"
                >
                  <option :value="null">Todas as etapas</option>
                  <option
                    v-for="stage in stages"
                    :key="stage.id"
                    :value="stage.id"
                  >
                    {{ stage.name }}
                  </option>
                </select>
                <div class="absolute right-2.5 top-0 bottom-0 flex items-center pointer-events-none">
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-4 text-n-slate-9"
                  />
                </div>
              </div>
            </div>

            <!-- Filtro por Etiqueta -->
            <div class="flex items-stretch gap-2">
              <div class="flex items-center justify-center" style="width: 16px; height: 42px;">
                <Icon icon="i-lucide-tag" class="size-4 text-n-slate-10" />
              </div>
              <div class="relative">
                <select
                  v-model="selectedLabelId"
                  class="px-3 pr-8 py-2.5 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm focus:outline-none focus:ring-2 focus:ring-n-blue-9 min-w-[150px] appearance-none cursor-pointer"
                  style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none; height: 42px;"
                >
                  <option :value="null">Todas as etiquetas</option>
                  <option
                    v-for="label in allLabels"
                    :key="label.id"
                    :value="label.id"
                  >
                    {{ label.title }}
                  </option>
                </select>
                <div class="absolute right-2.5 top-0 bottom-0 flex items-center pointer-events-none">
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-4 text-n-slate-9"
                  />
                </div>
              </div>
            </div>

            <!-- Filtro por Agente Atribuído -->
            <div class="flex items-stretch gap-2">
              <div class="flex items-center justify-center" style="width: 16px; height: 42px;">
                <Icon icon="i-lucide-user" class="size-4 text-n-slate-10" />
              </div>
              <div class="relative">
                <select
                  v-model="selectedAssigneeId"
                  class="px-3 pr-8 py-2.5 border border-n-weak rounded-lg bg-n-solid-3 text-n-slate-12 text-sm focus:outline-none focus:ring-2 focus:ring-n-blue-9 min-w-[150px] appearance-none cursor-pointer"
                  style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none; height: 42px;"
                >
                  <option :value="null">Todos os agentes</option>
                  <option
                    v-for="agent in allAgents"
                    :key="agent.id"
                    :value="agent.id"
                  >
                    {{ agent.name || agent.email }}
                  </option>
                </select>
                <div class="absolute right-2.5 top-0 bottom-0 flex items-center pointer-events-none">
                  <Icon
                    icon="i-lucide-chevron-down"
                    class="size-4 text-n-slate-9"
                  />
                </div>
              </div>
            </div>

            <!-- Limpar Filtros -->
            <button
              v-if="hasActiveFilters"
              @click="clearFilters"
              class="ml-auto px-3 py-2 text-sm text-n-slate-10 hover:text-n-slate-12 hover:bg-n-solid-3 rounded-lg transition-colors flex items-center gap-2"
            >
              <Icon icon="i-lucide-x" class="size-4" />
              Limpar filtros
            </button>

            <!-- Contador -->
            <div class="ml-auto flex items-center gap-2 text-sm text-n-slate-10">
              <Icon icon="i-lucide-list" class="size-4" />
              <span>
                <span class="font-semibold text-n-slate-12">{{ filteredItems.length }}</span>
                de {{ allItems.length }} conversas
              </span>
            </div>
          </div>
        </div>
              </div>

      <!-- Lista de Itens -->
      <div class="flex-1 overflow-y-auto">
        <div v-if="filteredItems.length === 0" class="flex flex-col items-center justify-center h-full min-h-[300px] bg-gradient-to-br from-n-background via-n-solid-1 to-n-background">
          <div class="mb-6 flex justify-center">
            <div class="size-20 rounded-2xl bg-gradient-to-br from-n-slate-4 to-n-slate-5 flex items-center justify-center shadow-lg border-2 border-n-slate-6">
              <Icon icon="i-lucide-search-x" class="size-10 text-n-slate-9" />
            </div>
          </div>
          <h3 class="text-xl font-bold text-n-slate-12 mb-2">Nenhum resultado encontrado</h3>
          <p class="text-base text-n-slate-11 mb-4">Tente ajustar os filtros de busca</p>
          <Button variant="ghost" size="sm" class="shadow-sm" @click="clearFilters">
            <Icon icon="i-lucide-x" class="size-4" />
            <span class="ml-2 font-medium">Limpar filtros</span>
          </Button>
              </div>

        <div v-else class="divide-y divide-n-weak">
          <div
            v-for="item in filteredItems"
            :key="item.id"
            class="p-4 hover:bg-n-solid-2 cursor-pointer transition-all duration-200 group border-l-4 border-transparent hover:border-n-teal-6 hover:shadow-sm"
            @click="openConversation(item)"
          >
            <div class="flex items-center gap-4">
              <!-- Avatar -->
                <div class="flex-shrink-0">
                <Avatar
                  :name="getContactName(item.conversationId)"
                  :src="getContactAvatar(item.conversationId)"
                  :size="48"
                  rounded-full
                />
                  </div>

              <!-- Informações Principais -->
              <div class="flex-1 min-w-0">
                <div class="flex items-start justify-between gap-4 mb-2">
                <div class="flex-1 min-w-0">
                    <h3 class="font-semibold text-base text-n-slate-12 mb-1 truncate">
                    {{ getContactName(item.conversationId) }}
                    </h3>
                    <div class="flex items-center gap-3 text-sm text-n-slate-10">
                      <span v-if="getContactPhone(item.conversationId)" class="flex items-center gap-1.5">
                        <Icon icon="i-lucide-phone" class="size-3.5" />
                        <span class="font-mono font-medium">{{ getContactPhone(item.conversationId) }}</span>
                      </span>
                    </div>
                    <div
                      v-if="getPendingScheduledCount(item.conversationId) > 0"
                      class="mt-2 inline-flex items-center gap-2 px-2.5 py-1 rounded-lg bg-n-teal-3 text-n-teal-11 text-xs font-semibold"
                    >
                      <Icon icon="i-lucide-clock-3" class="size-3.5" />
                      <span>
                        {{
                          t('KANBAN.SCHEDULED_MESSAGES.CONVERSATION_PENDING', {
                            count: getPendingScheduledCount(item.conversationId),
                          })
                        }}
                      </span>
                      <span v-if="getNextPendingScheduledAt(item.conversationId)" class="text-n-teal-10">
                        {{
                          format(new Date(getNextPendingScheduledAt(item.conversationId)), 'dd/MM HH:mm')
                        }}
                      </span>
                    </div>
                    <!-- Etiquetas -->
                    <div v-if="getConversationLabels(item.conversationId).length > 0" class="flex items-center gap-2 mt-2 flex-wrap">
                      <span
                        v-for="label in getConversationLabels(item.conversationId)"
                        :key="label.id"
                        class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium"
                        :style="{
                          backgroundColor: label.color ? `${label.color}20` : 'var(--n-solid-3)',
                          color: label.color || 'var(--n-slate-11)',
                        }"
                      >
                        <Icon icon="i-lucide-tag" class="size-3" />
                        {{ label.title }}
                      </span>
                    </div>
                  </div>

                  <!-- Status Badge -->
                  <div class="flex-shrink-0">
                    <span
                      :class="[
                        'inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold',
                        conversations[item.conversationId]?.status === 'open'
                          ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                          : conversations[item.conversationId]?.status === 'pending'
                          ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
                          : conversations[item.conversationId]?.status === 'resolved'
                          ? 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200'
                          : 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
                      ]"
                    >
                      <Icon
                        :icon="getStatusIcon(conversations[item.conversationId]?.status || 'open')"
                        class="size-3.5"
                      />
                      {{ getStatusTitle(conversations[item.conversationId]?.status || 'open') }}
                    </span>
                  </div>
                </div>

                <!-- Etapa e Ações -->
                <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span 
                  v-if="item.stageColor"
                  class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold text-white shadow-sm"
                  :style="{ backgroundColor: item.stageColor }"
                >
                  <div class="size-2 rounded-full bg-white/30"></div>
                  {{ item.stageName }}
                </span>
                <span v-else class="text-sm text-n-slate-11 font-medium">{{ item.stageName }}</span>
              </div>

                  <!-- Botões de Ação -->
                  <div
                    class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
                    @click.stop
                  >
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-clock"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.CREATE')"
                      class="!h-8 !w-8 !p-0"
                  @click="emit('schedule-message', conversations[item.conversationId])"
                />
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-list-checks"
                  :title="t('KANBAN.SCHEDULED_MESSAGES.MANAGE')"
                  class="!h-8 !w-8 !p-0"
                  @click="openScheduledManager(item.conversationId)"
                />
                <Button
                  size="xs"
                  variant="ghost"
                  icon="i-lucide-trash"
                  :title="t('KANBAN.ITEMS.REMOVE')"
                      class="!h-8 !w-8 !p-0 text-ruby-9 hover:text-ruby-10"
                  @click="handleRemove(item)"
                />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.list-view-container {
  background: var(--n-background);
}

/* Remover ícone padrão do select em todos os navegadores */
select {
  -webkit-appearance: none;
  -moz-appearance: none;
  appearance: none;
  background-image: none;
}

/* Para Firefox */
select::-moz-focus-inner {
  border: 0;
}

/* Para IE */
select::-ms-expand {
  display: none;
}
</style>
