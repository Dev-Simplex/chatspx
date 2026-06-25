<script setup>
import { ref, computed, watch, nextTick } from 'vue';
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

const DEFAULT_SLA_HOURS = 24;

const formData = ref({
  name: '',
  color: '#94a3b8',
  automation_type: null,
  wipLimit: '',
  slaHours: '',
});

const slaEnabled = ref(false);

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

const isResolvedStage = stage => {
  if (!stage) return false;
  if (stage.automation_type === 'resolved') return true;
  const name = (stage.name || '').toLowerCase();
  return name === 'resolvido' || name === 'resolvidos' || name === 'resolved';
};

// Reactive to the live dropdown too, so picking "Resolvido" hides SLA at once.
const stageIsResolved = computed(
  () =>
    formData.value.automation_type === 'resolved' ||
    isResolvedStage(props.stage)
);

// Default a sensible value the first time SLA is enabled.
watch(slaEnabled, enabled => {
  if (enabled && !String(formData.value.slaHours).trim()) {
    formData.value.slaHours = DEFAULT_SLA_HOURS;
  }
});

const toLimit = value => {
  if (String(value).trim() === '') return null;
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n >= 1 ? n : null;
};

// Merge WIP + SLA into the stage settings without clobbering other keys.
// Resolved stages never carry an SLA.
const buildSettings = () => {
  const base = { ...(props.stage?.settings || {}) };
  base.wip_limit = toLimit(formData.value.wipLimit);
  base.sla_hours =
    stageIsResolved.value || !slaEnabled.value
      ? null
      : toLimit(formData.value.slaHours);
  return base;
};

watch(
  () => props.stage,
  newStage => {
    if (newStage) {
      const slaHours = Number(newStage.settings?.sla_hours);
      const hasSla = Number.isFinite(slaHours) && slaHours > 0;
      const wip = Number(newStage.settings?.wip_limit);
      const hasWip = Number.isFinite(wip) && wip > 0;
      formData.value = {
        name: newStage.name || '',
        color: newStage.color || '#94a3b8',
        automation_type:
          newStage.automation_type !== undefined
            ? newStage.automation_type
            : null,
        wipLimit: hasWip ? wip : '',
        slaHours: hasSla ? slaHours : '',
      };
      slaEnabled.value = hasSla;
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
          settings: buildSettings(),
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
          settings: buildSettings(),
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
          settings: buildSettings(),
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

      <!-- Limite de cards (WIP) -->
      <div>
        <label
          for="stage-form-wip"
          class="block text-sm font-semibold mb-2 text-n-slate-12"
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-gauge" class="size-4" />
            {{ t('KANBAN.STAGES.WIP_LABEL') }}
          </div>
        </label>
        <input
          id="stage-form-wip"
          v-model="formData.wipLimit"
          type="number"
          min="1"
          step="1"
          class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
          :placeholder="t('KANBAN.STAGES.WIP_PLACEHOLDER')"
          @keydown.enter.prevent="save"
        />
      </div>

      <!-- SLA da etapa (em toda etapa, menos nas de resolvidas) -->
      <div v-if="!stageIsResolved">
        <label
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12 cursor-pointer select-none"
        >
          <input
            v-model="slaEnabled"
            type="checkbox"
            class="size-4 rounded border-n-weak text-n-teal-9 focus:ring-n-teal-9 cursor-pointer"
          />
          <Icon icon="i-lucide-clock" class="size-4" />
          {{ t('KANBAN.STAGES.SLA_ENABLE') }}
        </label>
        <div v-if="slaEnabled" class="mt-2 pl-6">
          <input
            id="stage-form-sla"
            v-model="formData.slaHours"
            type="number"
            min="1"
            step="1"
            class="w-full px-4 !py-3 !h-12 border border-n-weak rounded-xl bg-n-solid-1 text-n-slate-12 text-sm leading-5 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
            :placeholder="t('KANBAN.STAGES.SLA_HOURS_PLACEHOLDER')"
            @keydown.enter.prevent="save"
          />
          <p class="text-xs text-n-slate-10 mt-1">
            {{ t('KANBAN.STAGES.SLA_HINT') }}
          </p>
        </div>
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
