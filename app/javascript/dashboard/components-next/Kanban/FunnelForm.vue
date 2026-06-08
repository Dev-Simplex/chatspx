<script setup>
/* eslint-disable no-shadow, no-plusplus, no-continue, radix, no-await-in-loop, no-promise-executor-return, no-restricted-globals, no-alert */
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { isDefaultStage } from 'dashboard/composables/useKanbanStage';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  funnel: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  name: '',
  color: '#3b82f6',
  inbox_ids: [],
});

const normalizeInboxIds = ids => {
  if (!Array.isArray(ids)) {
    return [];
  }
  return ids.map(id => Number(id)).filter(id => Number.isFinite(id));
};

const stages = ref([]);
const isEditing = computed(() => !!props.funnel);
const isLoading = computed(
  () =>
    store.getters['kanban/getUIFlags'].isCreating ||
    store.getters['kanban/getUIFlags'].isUpdating
);

// Inboxes disponíveis
const availableInboxes = computed(() => {
  return store.getters['inboxes/getInboxes'] || [];
});

const dialogRef = ref(null);

watch(
  () => props.funnel,
  newFunnel => {
    if (newFunnel) {
      const inboxIds = normalizeInboxIds(
        newFunnel.inbox_ids ?? newFunnel.inboxIds ?? []
      );
      formData.value = {
        name: newFunnel.name || '',
        color: newFunnel.color || '#3b82f6',
        inbox_ids: inboxIds,
      };
      store.dispatch('kanban/fetchFunnelStages', newFunnel.id).then(() => {
        const fetchedStages = store.getters['kanban/getFunnelStages'](
          newFunnel.id
        );
        // Converter etapas existentes para o formato do formulário
        // IMPORTANTE: Preservar automation_type mesmo se for null/undefined para etapas padrão
        stages.value = fetchedStages.map(stage => ({
          id: stage.id,
          name: stage.name,
          color: stage.color || '#94a3b8',
          position: stage.position || 0,
          // Preservar automation_type do servidor - não usar || null que pode sobrescrever valores válidos
          automation_type:
            stage.automation_type !== undefined ? stage.automation_type : null,
        }));
      });
    } else {
      formData.value = {
        name: '',
        color: '#3b82f6',
        inbox_ids: [],
      };
      stages.value = [];
    }
  },
  { immediate: true }
);

// Usar watchEffect para garantir que o Dialog abra quando show mudar
watch(
  () => props.show,
  newShow => {
    if (newShow) {
      // Aguardar múltiplos ticks para garantir que o componente está montado
      nextTick(() => {
        setTimeout(() => {
          if (dialogRef.value && typeof dialogRef.value.open === 'function') {
            dialogRef.value.open();
          }
        }, 10);
      });
    } else if (dialogRef.value && typeof dialogRef.value.close === 'function') {
      dialogRef.value.close();
    }
  },
  { immediate: true }
);

onMounted(() => {
  // Carregar inboxes se ainda não foram carregadas
  if (availableInboxes.value.length === 0) {
    store.dispatch('inboxes/get');
  }

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

const toggleInbox = inboxId => {
  const normalizedInboxId = Number(inboxId);
  const index = formData.value.inbox_ids.indexOf(normalizedInboxId);
  if (index > -1) {
    formData.value.inbox_ids.splice(index, 1);
  } else {
    formData.value.inbox_ids.push(normalizedInboxId);
  }
  // Forçar reatividade
  formData.value = { ...formData.value };
};

const getChannelTypeLabel = channelType => {
  const channelTypes = {
    'Channel::WebWidget': t('KANBAN.CHANNEL_TYPES.WEB_WIDGET'),
    'Channel::Api': t('KANBAN.CHANNEL_TYPES.API'),
    'Channel::WhatsApp': t('KANBAN.CHANNEL_TYPES.WHATSAPP'),
    'Channel::Email': t('KANBAN.CHANNEL_TYPES.EMAIL'),
    'Channel::Sms': t('KANBAN.CHANNEL_TYPES.SMS'),
    'Channel::Telegram': t('KANBAN.CHANNEL_TYPES.TELEGRAM'),
    'Channel::Line': t('KANBAN.CHANNEL_TYPES.LINE'),
    'Channel::Twitter': t('KANBAN.CHANNEL_TYPES.TWITTER'),
    'Channel::Facebook': t('KANBAN.CHANNEL_TYPES.FACEBOOK'),
  };
  return channelTypes[channelType] || channelType;
};

const selectAllInboxes = () => {
  formData.value.inbox_ids = availableInboxes.value.map(inbox => inbox.id);
};

const clearAllInboxes = () => {
  formData.value.inbox_ids = [];
};

const addStage = () => {
  stages.value.push({
    id: `temp-${Date.now()}`,
    name: '',
    color: '#94a3b8',
    position: stages.value.length,
    automation_type: null,
    isNew: true,
  });
};

const removeStage = async index => {
  const stage = stages.value[index];

  // Não permitir deletar etapas padrão
  if (isDefaultStage(stage)) {
    alert(t('KANBAN.STAGES.CANNOT_DELETE_DEFAULT'));
    return;
  }

  // Se é uma etapa existente (tem ID numérico), deletar do servidor
  if (stage.id && !stage.id.toString().startsWith('temp-') && isEditing.value) {
    // eslint-disable-next-line no-restricted-globals, no-alert
    if (!confirm(t('KANBAN.STAGES.CONFIRM_DELETE'))) {
      return;
    }

    try {
      await store.dispatch('kanban/deleteStage', {
        funnelId: props.funnel.id,
        stageId: stage.id,
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('Erro ao deletar etapa:', error);
      alert(t('KANBAN.STAGES.DELETE_ERROR'));
      return;
    }
  }

  // Remover da lista local
  stages.value.splice(index, 1);
  stages.value.forEach((stage, idx) => {
    stage.position = idx;
  });
};

const save = async () => {
  if (!formData.value.name.trim()) {
    alert(t('KANBAN.FUNNELS.NAME_REQUIRED'));
    return;
  }

  try {
    formData.value = {
      ...formData.value,
      inbox_ids: normalizeInboxIds(formData.value.inbox_ids),
    };
    if (isEditing.value) {
      // Atualizar dados do funil
      await store.dispatch('kanban/updateFunnel', {
        funnelId: props.funnel.id,
        data: formData.value,
      });

      const funnelId = props.funnel.id;
      const existingStages = store.getters['kanban/getFunnelStages'](funnelId);
      const existingStageIds = existingStages.map(s => s.id);

      // Atualizar etapas existentes e criar novas
      for (let i = 0; i < stages.value.length; i++) {
        const stage = stages.value[i];

        if (!stage.name || !stage.name.trim()) {
          continue; // Pular etapas sem nome
        }

        // Se é uma etapa existente (tem ID numérico), atualizar
        if (
          stage.id &&
          !stage.id.toString().startsWith('temp-') &&
          existingStageIds.includes(parseInt(stage.id))
        ) {
          try {
            // Não atualizar etapas padrão, apenas permitir mudanças de cor
            if (isDefaultStage(stage)) {
              // Para etapas padrão, só atualizar se houver mudança na cor
              const existingStage = existingStages.find(s => s.id === stage.id);
              if (existingStage && existingStage.color !== stage.color) {
                await store.dispatch('kanban/updateStage', {
                  funnelId,
                  stageId: stage.id,
                  data: {
                    color: stage.color || '#94a3b8',
                  },
                });
              }
            } else {
              // Para etapas não padrão, atualizar tudo
              await store.dispatch('kanban/updateStage', {
                funnelId,
                stageId: stage.id,
                data: {
                  name: stage.name.trim(),
                  color: stage.color || '#94a3b8',
                  position: i,
                  automation_type: stage.automation_type || null,
                },
              });
            }
            await new Promise(resolve => setTimeout(resolve, 150));
          } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Erro ao atualizar etapa:', error);
            // Não bloquear se falhar atualização
          }
        }
        // Se é uma etapa nova, criar
        else if (!stage.id || stage.id.toString().startsWith('temp-')) {
          try {
            await store.dispatch('kanban/createStage', {
              funnelId,
              data: {
                name: stage.name.trim(),
                color: stage.color || '#94a3b8',
                position: i,
                automation_type: stage.automation_type || null,
              },
            });
            await new Promise(resolve => setTimeout(resolve, 200));
          } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Erro ao criar etapa:', error);
            alert(
              `Erro ao criar etapa "${stage.name}": ${error.message || error}`
            );
          }
        }
      }

      // Buscar etapas atualizadas
      await new Promise(resolve => setTimeout(resolve, 300));
      await store.dispatch('kanban/fetchFunnelStages', funnelId);
    } else {
      const response = await store.dispatch(
        'kanban/createFunnel',
        formData.value
      );
      const funnelId = response.data.id;

      // Criar etapas sequencialmente e aguardar cada uma
      const validStages = stages.value.filter(
        stage => stage.name && stage.name.trim()
      );
      const createdStages = [];

      for (let i = 0; i < validStages.length; i++) {
        const stage = validStages[i];
        try {
          const stageResponse = await store.dispatch('kanban/createStage', {
            funnelId,
            data: {
              name: stage.name.trim(),
              color: stage.color || '#94a3b8',
              position: i,
              automation_type: stage.automation_type || null,
            },
          });
          if (stageResponse && stageResponse.data) {
            createdStages.push(stageResponse.data);
            // eslint-disable-next-line no-console
            console.log('Etapa criada:', stageResponse.data);
          }
          // Delay entre criações para evitar problemas de concorrência
          await new Promise(resolve => setTimeout(resolve, 150));
        } catch (error) {
          // eslint-disable-next-line no-console
          console.error('Erro ao criar etapa:', error);
          alert(
            `Erro ao criar etapa "${stage.name}": ${error.message || error}`
          );
        }
      }

      // Sempre buscar etapas após criar para garantir sincronização
      if (createdStages.length > 0) {
        await new Promise(resolve => setTimeout(resolve, 300));
        await store.dispatch('kanban/fetchFunnelStages', funnelId);
      }
    }

    emit('saved');
    emit('close');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao salvar funil:', error);
    alert(t('KANBAN.FUNNELS.SAVE_ERROR'));
  }
};

const close = () => {
  emit('close');
};

const handleDeleteFunnel = async () => {
  if (!isEditing.value || !props.funnel) return;

  // eslint-disable-next-line no-restricted-globals, no-alert

  if (!confirm(t('KANBAN.FUNNELS.CONFIRM_DELETE'))) {
    return;
  }

  try {
    await store.dispatch('kanban/deleteFunnel', props.funnel.id);
    emit('saved'); // Para atualizar a lista
    emit('close');
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao deletar funil:', error);
    alert(t('KANBAN.FUNNELS.DELETE_ERROR'));
  }
};
</script>

<template>
  <Dialog
    v-if="show"
    ref="dialogRef"
    :title="isEditing ? t('KANBAN.FUNNELS.EDIT') : t('KANBAN.FUNNELS.CREATE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
    width="2xl"
    @close="() => emit('close')"
  >
    <div class="space-y-6" @submit.prevent.stop>
      <!-- Funnel Name -->
      <div>
        <label
          for="funnel-name"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-tag" class="size-4" />
            {{ t('KANBAN.FUNNELS.NAME') }}
          </div>
        </label>
        <input
          id="funnel-name"
          v-model="formData.name"
          type="text"
          class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
          :placeholder="t('KANBAN.FUNNELS.NAME_PLACEHOLDER')"
          @keydown.enter.prevent="save"
        />
      </div>

      <!-- Funnel Color -->
      <div>
        <label
          for="funnel-color"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-palette" class="size-4" />
            {{ t('KANBAN.FUNNELS.COLOR') }}
          </div>
        </label>
        <div class="flex items-center gap-3">
          <input
            id="funnel-color"
            v-model="formData.color"
            type="color"
            class="w-16 h-16 border border-n-weak rounded-xl cursor-pointer"
          />
          <div
            class="flex-1 px-4 py-3 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 font-mono"
          >
            {{ formData.color }}
          </div>
        </div>
      </div>

      <!-- Inboxes Filter -->
      <div>
        <label class="block text-sm font-semibold mb-3 text-n-slate-12">
          <div class="flex items-center gap-2 mb-1">
            <Icon icon="i-lucide-inbox" class="size-4" />
            {{ t('KANBAN.FUNNELS.INBOXES') }}
          </div>
          <p class="text-xs text-n-slate-10 font-normal">
            {{ t('KANBAN.FUNNELS.INBOXES_DESCRIPTION') }}
          </p>
        </label>
        <div
          class="border border-n-weak rounded-xl bg-n-solid-1 p-4 max-h-[200px] overflow-y-auto"
        >
          <div
            v-if="availableInboxes.length === 0"
            class="text-sm text-n-slate-10 text-center py-4"
          >
            {{ t('KANBAN.FUNNELS.NO_INBOXES') }}
          </div>
          <div v-else class="space-y-2">
            <label
              v-for="inbox in availableInboxes"
              :key="inbox.id"
              class="flex items-center gap-3 p-2 rounded-lg hover:bg-n-slate-3/50 cursor-pointer transition-colors"
              @click.prevent="toggleInbox(inbox.id)"
            >
              <input
                type="checkbox"
                :value="inbox.id"
                :checked="formData.inbox_ids.includes(inbox.id)"
                class="w-4 h-4 text-n-teal-9 border-n-weak rounded focus:ring-2 focus:ring-n-teal-9 cursor-pointer"
                @click.stop
                @change="toggleInbox(inbox.id)"
              />
              <div class="flex-1">
                <div class="text-sm font-medium text-n-slate-12">
                  {{ inbox.name }}
                </div>
                <div v-if="inbox.channel_type" class="text-xs text-n-slate-10">
                  {{ getChannelTypeLabel(inbox.channel_type) }}
                </div>
              </div>
            </label>
          </div>
        </div>
        <div class="flex items-center justify-between mt-2">
          <button
            type="button"
            class="text-xs text-n-teal-9 hover:text-n-teal-10 font-medium"
            @click="selectAllInboxes"
          >
            {{ t('KANBAN.FUNNELS.SELECT_ALL') }}
          </button>
          <button
            type="button"
            class="text-xs text-n-slate-10 hover:text-n-slate-11 font-medium"
            @click="clearAllInboxes"
          >
            {{ t('KANBAN.FUNNELS.CLEAR_ALL') }}
          </button>
        </div>
      </div>

      <!-- Stages (always show, can add when editing) -->
      <div>
        <div class="flex items-center justify-between mb-3">
          <label class="block text-sm font-semibold text-n-slate-12">
            <div class="flex items-center gap-2">
              <Icon icon="i-lucide-git-branch" class="size-4" />
              {{ t('KANBAN.STAGES.TITLE') }}
            </div>
          </label>
          <Button
            size="sm"
            variant="ghost"
            icon="i-lucide-plus"
            @click="addStage"
          >
            {{ t('KANBAN.STAGES.CREATE') }}
          </Button>
        </div>
        <div class="space-y-3">
          <div
            v-for="(stage, index) in stages"
            :key="stage.id || `stage-${index}`"
            class="group flex flex-col sm:flex-row gap-3 items-start sm:items-center p-4 bg-n-solid-1 rounded-xl border border-n-weak hover:border-n-teal-9 transition-colors"
          >
            <div
              class="flex-1 w-full sm:w-auto space-y-2 sm:space-y-0 sm:flex sm:items-center sm:gap-3"
            >
              <div class="flex-1 min-w-0">
                <label
                  :for="`stage-name-${index}`"
                  class="block text-xs font-medium text-n-slate-11 mb-1"
                >
                  {{ t('KANBAN.STAGES.NAME') }}
                </label>
                <input
                  :id="`stage-name-${index}`"
                  v-model="stage.name"
                  type="text"
                  class="w-full px-3 py-2 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-teal-9 text-sm"
                  :placeholder="t('KANBAN.STAGES.NAME_PLACEHOLDER')"
                  :disabled="isDefaultStage(stage)"
                />
              </div>
              <div class="flex items-center gap-2">
                <div>
                  <label
                    :for="`stage-color-${index}`"
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                  >
                    {{ t('KANBAN.STAGES.COLOR') }}
                  </label>
                  <div class="flex items-center gap-2">
                    <input
                      :id="`stage-color-${index}`"
                      v-model="stage.color"
                      type="color"
                      class="w-10 h-10 border border-n-weak rounded-xl cursor-pointer"
                      :disabled="isDefaultStage(stage)"
                    />
                    <span class="text-xs text-n-slate-10 font-mono">{{
                      stage.color
                    }}</span>
                  </div>
                </div>
              </div>
              <div class="flex-1 min-w-[150px]">
                <label
                  :for="`stage-automation-${index}`"
                  class="block text-xs font-medium text-n-slate-11 mb-1"
                >
                  {{ t('KANBAN.STAGES.AUTOMATION_TYPE') }}
                </label>
                <select
                  :id="`stage-automation-${index}`"
                  v-model="stage.automation_type"
                  class="w-full px-3 py-2 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-teal-9 text-sm disabled:opacity-75 disabled:cursor-not-allowed"
                  :disabled="isDefaultStage(stage)"
                >
                  <option :value="null">
                    {{ t('KANBAN.STAGES.NO_AUTOMATION') }}
                  </option>
                  <option value="open">
                    {{ t('KANBAN.STAGES.AUTOMATION_OPEN') }}
                  </option>
                  <option value="resolved">
                    {{ t('KANBAN.STAGES.AUTOMATION_RESOLVED') }}
                  </option>
                </select>
              </div>
            </div>
            <div class="flex items-center gap-2 self-end sm:self-center">
              <div
                v-if="isDefaultStage(stage)"
                class="px-2 py-1 text-xs font-semibold bg-n-teal-4 text-n-teal-12 rounded border border-n-teal-6"
                :title="t('KANBAN.STAGES.DEFAULT_STAGE_TOOLTIP')"
              >
                {{ t('KANBAN.STAGES.DEFAULT') }}
              </div>
              <Button
                size="sm"
                variant="ghost"
                icon="i-lucide-trash"
                color="ruby"
                class="opacity-70 hover:opacity-100 transition-opacity"
                :title="
                  isDefaultStage(stage)
                    ? t('KANBAN.STAGES.CANNOT_DELETE_DEFAULT')
                    : t('KANBAN.STAGES.DELETE')
                "
                :disabled="isDefaultStage(stage)"
                @click="removeStage(index)"
              />
            </div>
          </div>
          <div
            v-if="stages.length === 0"
            class="text-center py-8 text-n-slate-10 border-2 border-dashed border-n-weak rounded-xl"
          >
            <Icon
              icon="i-lucide-git-branch"
              class="size-8 mx-auto mb-2 opacity-50"
            />
            <p class="text-sm">{{ t('KANBAN.STAGES.ADD_FIRST_STAGE') }}</p>
          </div>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-between items-center">
        <Button
          v-if="isEditing"
          variant="ghost"
          icon="i-lucide-trash"
          color="ruby"
          :is-loading="isLoading"
          @click="handleDeleteFunnel"
        >
          <span class="ml-2">{{ t('KANBAN.FUNNELS.DELETE') }}</span>
        </Button>
        <div v-else />
        <div class="flex gap-3">
          <Button variant="ghost" icon="i-lucide-x" @click="close">
            <span class="ml-2">{{ t('KANBAN.CANCEL') }}</span>
          </Button>
          <Button
            :is-loading="isLoading"
            color="blue"
            icon="i-lucide-check"
            type="button"
            @click="save"
          >
            <span class="ml-2">{{ t('KANBAN.SAVE') }}</span>
          </Button>
        </div>
      </div>
    </template>
  </Dialog>
</template>
