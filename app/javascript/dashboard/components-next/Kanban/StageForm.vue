<script setup>
import { ref, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  stage: {
    type: Object,
    default: null,
  },
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const formData = ref({
  name: '',
  color: '#94a3b8',
  automation_type: null,
});

const dialogRef = ref(null);
const isLoading = ref(false);

const isDefaultStage = stage => {
  if (!stage) return false;
  const isDefaultByName =
    stage.name === 'Abertos' ||
    stage.name === 'Resolvidos' ||
    stage.name === 'Em Andamento';
  const isDefaultByAutomation =
    stage.automation_type === 'open' || stage.automation_type === 'resolved';
  return isDefaultByName || isDefaultByAutomation;
};

watch(
  () => props.stage,
  newStage => {
    if (newStage) {
      formData.value = {
        name: newStage.name || '',
        color: newStage.color || '#94a3b8',
        automation_type:
          newStage.automation_type !== undefined
            ? newStage.automation_type
            : null,
      };
    }
  },
  { immediate: true }
);

watch(
  () => props.show,
  newShow => {
    if (newShow) {
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

const close = () => {
  emit('close');
};

const save = async () => {
  if (!props.funnelId) {
    close();
    return;
  }

  const stage = props.stage;
  const isDefault = isDefaultStage(stage);
  const isCreate = !stage?.id;

  if ((!isDefault || isCreate) && !formData.value.name?.trim()) {
    useAlert(t('KANBAN.STAGES.NAME_REQUIRED') || 'Nome da etapa é obrigatório');
    return;
  }

  if (isCreate) {
    isLoading.value = true;
    try {
      await store.dispatch('kanban/createStage', {
        funnelId: props.funnelId,
        data: {
          name: formData.value.name.trim(),
          color: formData.value.color || '#94a3b8',
          automation_type: formData.value.automation_type || null,
        },
      });
      emit('saved');
      close();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('StageForm: Erro ao criar etapa', error);
      useAlert(t('KANBAN.STAGES.SAVE_ERROR') || 'Erro ao salvar etapa');
    } finally {
      isLoading.value = false;
    }
    return;
  }

  isLoading.value = true;
  try {
    if (isDefault) {
      await store.dispatch('kanban/updateStage', {
        funnelId: props.funnelId,
        stageId: stage.id,
        data: {
          color: formData.value.color || '#94a3b8',
        },
      });
    } else {
      await store.dispatch('kanban/updateStage', {
        funnelId: props.funnelId,
        stageId: stage.id,
        data: {
          name: formData.value.name.trim(),
          color: formData.value.color || '#94a3b8',
          automation_type: formData.value.automation_type || null,
        },
      });
    }
    emit('saved');
    close();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('StageForm: Erro ao atualizar etapa', error);
    useAlert(t('KANBAN.STAGES.SAVE_ERROR') || 'Erro ao salvar etapa');
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <Dialog
    v-if="show && stage"
    ref="dialogRef"
    :title="
      stage && stage.id ? t('KANBAN.STAGES.EDIT') : t('KANBAN.STAGES.CREATE')
    "
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
    width="md"
    @close="close"
  >
    <div class="space-y-4">
      <!-- Nome da etapa -->
      <div v-if="!isDefaultStage(stage)">
        <label
          for="stage-form-name"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-tag" class="size-4" />
            {{ t('KANBAN.STAGES.NAME') }}
          </div>
        </label>
        <input
          id="stage-form-name"
          v-model="formData.name"
          type="text"
          class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
          :placeholder="t('KANBAN.STAGES.NAME_PLACEHOLDER')"
          @keydown.enter.prevent="save"
        />
      </div>

      <!-- Cor da etapa -->
      <div>
        <label
          for="stage-form-color"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-palette" class="size-4" />
            {{ t('KANBAN.STAGES.COLOR') }}
          </div>
        </label>
        <div class="flex items-center gap-3">
          <input
            id="stage-form-color"
            v-model="formData.color"
            type="color"
            class="w-12 h-12 border border-n-weak rounded-xl cursor-pointer"
          />
          <span
            class="px-4 py-3 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 font-mono text-sm"
          >
            {{ formData.color }}
          </span>
        </div>
      </div>

      <!-- Tipo de automação -->
      <div v-if="!isDefaultStage(stage)">
        <label
          for="stage-form-automation"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-zap" class="size-4" />
            {{ t('KANBAN.STAGES.AUTOMATION_TYPE') }}
          </div>
        </label>
        <select
          id="stage-form-automation"
          v-model="formData.automation_type"
          class="w-full px-4 py-3 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-teal-9 text-sm"
        >
          <option :value="null">{{ t('KANBAN.STAGES.NO_AUTOMATION') }}</option>
          <option value="open">{{ t('KANBAN.STAGES.AUTOMATION_OPEN') }}</option>
          <option value="resolved">
            {{ t('KANBAN.STAGES.AUTOMATION_RESOLVED') }}
          </option>
        </select>
      </div>

      <div
        v-if="isDefaultStage(stage)"
        class="text-xs text-n-slate-10 bg-n-teal-4 text-n-teal-12 rounded-lg px-3 py-2 border border-n-teal-6"
      >
        {{ t('KANBAN.STAGES.DEFAULT_STAGE_TOOLTIP') }}
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end gap-3">
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
    </template>
  </Dialog>
</template>
