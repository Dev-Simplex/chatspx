<script setup>
import { ref, watch, nextTick, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import SearchAPI from 'dashboard/api/search';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  funnelId: {
    type: Number,
    required: true,
  },
  stage: {
    type: Object,
    default: null,
  },
  // Quando presente, o modal edita um cartão de TAREFA existente.
  editItem: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'added']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const isEditing = computed(() => Boolean(props.editItem));
// 'search' (buscar conversa) | 'task' (criar/editar tarefa avulsa)
const mode = ref('search');

// ── Busca de conversa ──────────────────────────────────────────────────
const searchQuery = ref('');
const results = ref([]);
const isSearching = ref(false);
const isAdding = ref(false);

// ── Tarefa/lembrete ────────────────────────────────────────────────────
const taskTitle = ref('');
const taskDescription = ref('');
const taskAssigneeId = ref('');
const isSavingTask = ref(false);
const agents = computed(() => store.getters['agents/getAgents'] || []);

const dialogTitle = computed(() => {
  if (isEditing.value) return t('KANBAN.TASK.EDIT_TITLE');
  if (mode.value === 'task') return t('KANBAN.TASK.CREATE_TITLE');
  return t('KANBAN.ITEMS.ADD');
});

const resolveContact = conversation =>
  conversation?.meta?.sender ||
  conversation?.contact ||
  conversation?.sender ||
  {};

const lastMessageText = conversation => {
  const message =
    conversation?.last_non_activity_message ||
    conversation?.last_message ||
    conversation?.meta?.last_non_activity_message;
  return message?.content || '';
};

const runSearch = debounce(async query => {
  const term = (query || '').trim();
  if (term.length < 2) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  isSearching.value = true;
  try {
    const { data } = await SearchAPI.conversations({ q: term });
    results.value = data?.payload?.conversations || data?.payload || [];
  } catch (_) {
    results.value = [];
  } finally {
    isSearching.value = false;
  }
}, 350);

watch(searchQuery, query => runSearch(query));

watch(
  () => props.show,
  newShow => {
    if (newShow) {
      searchQuery.value = '';
      results.value = [];
      store.dispatch('agents/get');
      if (isEditing.value) {
        mode.value = 'task';
        taskTitle.value = props.editItem.title || '';
        taskDescription.value = props.editItem.description || '';
        taskAssigneeId.value = props.editItem.assignee_id || '';
      } else {
        mode.value = 'search';
        taskTitle.value = '';
        taskDescription.value = '';
        taskAssigneeId.value = '';
      }
      nextTick(() => {
        setTimeout(() => dialogRef.value?.open?.(), 10);
      });
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);

const close = () => emit('close');

const addConversation = async conversation => {
  const conversationId = conversation?.id;
  const stageId = props.stage?.id;
  if (!conversationId || !stageId || isAdding.value) return;

  isAdding.value = true;
  try {
    await store.dispatch('kanban/createItem', {
      funnelId: props.funnelId,
      data: {
        conversation_id: conversationId,
        funnel_stage_id: stageId,
      },
    });
    useAlert(t('KANBAN.ITEMS.ADD_SUCCESS'));
    emit('added', { conversationId, stageId });
    close();
  } catch (error) {
    const status = error?.response?.status;
    const message =
      status === 422
        ? t('KANBAN.ITEMS.ADD_DUPLICATE')
        : t('KANBAN.ITEMS.ADD_ERROR');
    useAlert(message);
  } finally {
    isAdding.value = false;
  }
};

const saveTask = async () => {
  const title = taskTitle.value.trim();
  if (!title || isSavingTask.value) return;

  isSavingTask.value = true;
  const data = {
    title,
    description: taskDescription.value.trim(),
    assignee_id: taskAssigneeId.value || null,
  };
  try {
    if (isEditing.value) {
      await store.dispatch('kanban/updateItem', {
        funnelId: props.funnelId,
        itemId: props.editItem.id,
        data,
      });
      useAlert(t('KANBAN.TASK.SAVE_SUCCESS'));
    } else {
      await store.dispatch('kanban/createItem', {
        funnelId: props.funnelId,
        data: { ...data, funnel_stage_id: props.stage?.id },
      });
      useAlert(t('KANBAN.TASK.CREATE_SUCCESS'));
    }
    emit('added');
    close();
  } catch (_) {
    useAlert(t('KANBAN.TASK.ERROR'));
  } finally {
    isSavingTask.value = false;
  }
};

const deleteTask = async () => {
  if (!isEditing.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('KANBAN.TASK.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('kanban/deleteItem', {
      funnelId: props.funnelId,
      itemId: props.editItem.id,
    });
    useAlert(t('KANBAN.TASK.DELETE_SUCCESS'));
    emit('added');
    close();
  } catch (_) {
    useAlert(t('KANBAN.TASK.ERROR'));
  }
};
</script>

<template>
  <Dialog
    v-if="show && (stage || editItem)"
    ref="dialogRef"
    :title="dialogTitle"
    :description="stage ? stage.name : ''"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="md"
    full-height
    @close="close"
  >
    <!-- `full-height` + este scroll: sem eles, em tela baixa o conteúdo passava do
         teto do <dialog> sem barra de rolagem, e o botão de salvar ficava
         inalcançável (o dialog é `fixed`, não há scroll de página que o traga). -->
    <div class="min-h-0 flex-1 space-y-4 overflow-y-auto">
      <!-- Alternância buscar conversa | criar tarefa (só ao adicionar) -->
      <div
        v-if="!isEditing"
        class="flex gap-1 rounded-lg border border-n-weak bg-n-alpha-1 p-1"
      >
        <button
          class="flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition"
          :class="
            mode === 'search'
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="mode = 'search'"
        >
          {{ t('KANBAN.TASK.TAB_SEARCH') }}
        </button>
        <button
          class="flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition"
          :class="
            mode === 'task'
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="mode = 'task'"
        >
          {{ t('KANBAN.TASK.TAB_CREATE') }}
        </button>
      </div>

      <!-- ============ Buscar conversa ============ -->
      <template v-if="mode === 'search' && !isEditing">
        <div class="relative">
          <Icon
            icon="i-lucide-search"
            class="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="searchQuery"
            type="search"
            autofocus
            :placeholder="t('KANBAN.ITEMS.ADD_SEARCH_PLACEHOLDER')"
            class="h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 !pl-11 pr-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

        <div class="max-h-80 overflow-y-auto">
          <div
            v-if="isSearching"
            class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10"
          >
            <Icon icon="i-lucide-loader-2" class="size-4 animate-spin" />
            {{ t('KANBAN.LOADING') }}
          </div>

          <div
            v-else-if="searchQuery.trim().length >= 2 && !results.length"
            class="py-8 text-center text-sm text-n-slate-10"
          >
            {{ t('KANBAN.ITEMS.ADD_NO_RESULTS') }}
          </div>

          <ul v-else class="flex flex-col gap-1">
            <li v-for="conversation in results" :key="conversation.id">
              <button
                class="flex w-full items-center gap-3 rounded-xl border border-transparent p-2.5 text-left transition hover:border-n-weak hover:bg-n-alpha-1 disabled:opacity-50"
                :disabled="isAdding"
                @click="addConversation(conversation)"
              >
                <Avatar
                  :name="resolveContact(conversation).name || ''"
                  :src="
                    resolveContact(conversation).thumbnail ||
                    resolveContact(conversation).avatar_url
                  "
                  :size="32"
                  rounded-full
                />
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-n-slate-12">
                    {{
                      resolveContact(conversation).name ||
                      t('KANBAN.ITEMS.UNNAMED_CONTACT')
                    }}
                    <span class="text-n-slate-9">#{{ conversation.id }}</span>
                  </p>
                  <p
                    v-if="lastMessageText(conversation)"
                    class="truncate text-xs text-n-slate-10"
                  >
                    {{ lastMessageText(conversation) }}
                  </p>
                </div>
                <Icon
                  icon="i-lucide-plus"
                  class="size-4 shrink-0 text-n-slate-10"
                />
              </button>
            </li>
          </ul>

          <div
            v-if="!searchQuery.trim()"
            class="py-8 text-center text-xs text-n-slate-9"
          >
            {{ t('KANBAN.ITEMS.ADD_HINT') }}
          </div>
        </div>
      </template>

      <!-- ============ Criar / editar tarefa ============ -->
      <template v-else>
        <div class="space-y-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.TASK.TITLE_LABEL') }}
          </label>
          <input
            v-model="taskTitle"
            type="text"
            autofocus
            :placeholder="t('KANBAN.TASK.TITLE_PLACEHOLDER')"
            class="h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @keydown.enter.exact.prevent="saveTask"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.TASK.DESC_LABEL') }}
          </label>
          <textarea
            v-model="taskDescription"
            rows="3"
            :placeholder="t('KANBAN.TASK.DESC_PLACEHOLDER')"
            class="w-full resize-none rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.TASK.ASSIGNEE_LABEL') }}
          </label>
          <select
            v-model="taskAssigneeId"
            class="h-11 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
            <option value="">{{ t('KANBAN.TASK.ASSIGNEE_NONE') }}</option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </div>

        <div class="flex items-center justify-between gap-2 pt-1">
          <Button
            v-if="isEditing"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :label="t('KANBAN.TASK.DELETE')"
            @click="deleteTask"
          />
          <span v-else />
          <Button
            color="blue"
            icon="i-lucide-check"
            :label="isEditing ? t('KANBAN.TASK.SAVE') : t('KANBAN.TASK.CREATE')"
            :is-loading="isSavingTask"
            :disabled="!taskTitle.trim() || isSavingTask"
            @click="saveTask"
          />
        </div>
      </template>
    </div>
  </Dialog>
</template>
