<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  item: {
    type: Object,
    default: null,
  },
  funnelId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'moved']);

const store = useStore();
const { t } = useI18n();

const selectedStageId = ref(null);
const dialogRef = ref(null);

const stages = computed(() =>
  store.getters['kanban/getFunnelStages'](props.funnelId)
);

watch(
  () => props.show,
  async (newShow) => {
    if (newShow && props.item) {
      selectedStageId.value = props.item.funnelStageId;
      await store.dispatch('kanban/fetchFunnelStages', props.funnelId);
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

const move = async () => {
  if (!selectedStageId.value) {
    alert(t('KANBAN.ITEMS.STAGE_REQUIRED'));
    return;
  }

  try {
    await store.dispatch('kanban/updateItem', {
      funnelId: props.funnelId,
      itemId: props.item.id,
      data: {
        funnel_stage_id: selectedStageId.value,
      },
    });

    emit('moved');
    emit('close');
  } catch (error) {
    console.error('Erro ao mover item:', error);
    alert(t('KANBAN.ITEMS.MOVE_ERROR'));
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
    :title="t('KANBAN.ITEMS.MOVE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="() => emit('close')"
  >
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-semibold mb-2 text-n-slate-12">
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-git-branch" class="size-4" />
            {{ t('KANBAN.STAGES.TITLE') }}
          </div>
        </label>
        <div class="space-y-2 max-h-64 overflow-y-auto">
          <div
            v-for="stage in stages"
            :key="stage.id"
            :class="[
              'flex items-center gap-3 p-3 rounded-lg border cursor-pointer transition-colors',
              selectedStageId === stage.id
                ? 'bg-n-teal-3 border-n-teal-9'
                : 'bg-n-solid-3 border-n-weak hover:bg-n-solid-4',
            ]"
            @click="selectedStageId = stage.id"
          >
            <div
              v-if="stage.color"
              :class="['w-4 h-4 rounded-full flex-shrink-0']"
              :style="{ backgroundColor: stage.color }"
            />
            <span class="text-sm font-medium text-n-slate-12 flex-1">
              {{ stage.name }}
            </span>
            <Icon
              v-if="selectedStageId === stage.id"
              icon="i-lucide-check"
              class="size-4 text-n-teal-9"
            />
          </div>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end gap-3">
        <Button variant="ghost" icon="i-lucide-x" @click="close">
          <span class="ml-2">{{ t('KANBAN.CANCEL') }}</span>
        </Button>
        <Button color="blue" icon="i-lucide-move" @click="move">
          <span class="ml-2">{{ t('KANBAN.MOVE') }}</span>
        </Button>
      </div>
    </template>
  </Dialog>
</template>
