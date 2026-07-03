<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { FIELD_TYPES } from './composables/useCustomFields';

const props = defineProps({
  funnelId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const fields = computed(() =>
  store.getters['kanban/getFunnelCustomFields'](props.funnelId)
);

const isBusy = ref(false);
const draft = ref({
  label: '',
  fieldType: 'text',
  showOnCard: true,
  choices: '',
});

const typeOptions = FIELD_TYPES;
const isDropdown = computed(() => draft.value.fieldType === 'dropdown');

onMounted(() => {
  store.dispatch('kanban/fetchCustomFields', props.funnelId).catch(() => {});
});

// Derive a safe, unique key from the label (matches backend /\A[a-z][a-z0-9_]*\z/).
const slugify = label => {
  let key = String(label || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!/^[a-z]/.test(key)) key = `f_${key}`;
  return key || 'campo';
};

const uniqueKey = base => {
  const existing = new Set(fields.value.map(f => f.key));
  if (!existing.has(base)) return base;
  let i = 2;
  while (existing.has(`${base}_${i}`)) i += 1;
  return `${base}_${i}`;
};

const buildOptions = () => {
  if (!isDropdown.value) return {};
  const choices = draft.value.choices
    .split(',')
    .map(c => c.trim())
    .filter(Boolean);
  return { choices };
};

const resetDraft = () => {
  draft.value = { label: '', fieldType: 'text', showOnCard: true, choices: '' };
};

const addField = async () => {
  const label = draft.value.label.trim();
  if (!label || isBusy.value) return;
  isBusy.value = true;
  try {
    await store.dispatch('kanban/createCustomField', {
      funnelId: props.funnelId,
      data: {
        label,
        key: uniqueKey(slugify(label)),
        field_type: draft.value.fieldType,
        show_on_card: draft.value.showOnCard,
        position: fields.value.length,
        options: buildOptions(),
      },
    });
    resetDraft();
  } catch (error) {
    const message =
      error?.response?.data?.errors?.join(', ') ||
      t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR');
    useAlert(message);
  } finally {
    isBusy.value = false;
  }
};

const toggleShowOnCard = async field => {
  if (isBusy.value) return;
  isBusy.value = true;
  try {
    await store.dispatch('kanban/updateCustomField', {
      funnelId: props.funnelId,
      fieldId: field.id,
      data: { show_on_card: !field.showOnCard },
    });
  } catch (_) {
    useAlert(t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
  } finally {
    isBusy.value = false;
  }
};

const removeField = async field => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('KANBAN.CUSTOM_FIELDS.DELETE_CONFIRM', { label: field.label })
    )
  )
    return;
  isBusy.value = true;
  try {
    await store.dispatch('kanban/deleteCustomField', {
      funnelId: props.funnelId,
      fieldId: field.id,
    });
  } catch (_) {
    useAlert(t('KANBAN.CUSTOM_FIELDS.SAVE_ERROR'));
  } finally {
    isBusy.value = false;
  }
};

const typeLabel = type => t(`KANBAN.CUSTOM_FIELDS.TYPES.${type.toUpperCase()}`);
</script>

<template>
  <div class="flex flex-col gap-2">
    <!-- Existing fields -->
    <ul v-if="fields.length" class="flex flex-col gap-1">
      <li
        v-for="field in fields"
        :key="field.id"
        class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
      >
        <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
          {{ field.label }}
        </span>
        <span class="shrink-0 text-[11px] text-n-slate-10">
          {{ typeLabel(field.fieldType) }}
        </span>
        <button
          type="button"
          class="shrink-0 rounded px-1.5 py-0.5 text-[11px] font-medium transition"
          :class="
            field.showOnCard
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-slate-3 text-n-slate-10'
          "
          :title="t('KANBAN.CUSTOM_FIELDS.SHOW_ON_CARD')"
          @click="toggleShowOnCard(field)"
        >
          <Icon
            :icon="field.showOnCard ? 'i-lucide-eye' : 'i-lucide-eye-off'"
            class="size-3"
          />
        </button>
        <button
          type="button"
          class="shrink-0 rounded p-1 text-n-ruby-11 transition hover:bg-n-ruby-3"
          :title="t('KANBAN.CUSTOM_FIELDS.DELETE')"
          @click="removeField(field)"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
        </button>
      </li>
    </ul>
    <p v-else class="text-xs text-n-slate-10">
      {{ t('KANBAN.CUSTOM_FIELDS.EMPTY') }}
    </p>

    <!-- Add a new field -->
    <div class="rounded-lg border border-dashed border-n-weak p-2">
      <div class="flex flex-wrap items-center gap-2">
        <input
          v-model="draft.label"
          type="text"
          class="kanban-cf-editor-input min-w-[8rem] flex-1"
          :placeholder="t('KANBAN.CUSTOM_FIELDS.LABEL_PLACEHOLDER')"
          @keyup.enter="addField"
        />
        <select v-model="draft.fieldType" class="kanban-cf-editor-input">
          <option
            v-for="opt in typeOptions"
            :key="opt.value"
            :value="opt.value"
          >
            {{ typeLabel(opt.value) }}
          </option>
        </select>
        <label
          class="flex items-center gap-1 text-[11px] text-n-slate-11"
          :title="t('KANBAN.CUSTOM_FIELDS.SHOW_ON_CARD')"
        >
          <input v-model="draft.showOnCard" type="checkbox" class="size-3.5" />
          {{ t('KANBAN.CUSTOM_FIELDS.ON_CARD_SHORT') }}
        </label>
        <Button
          size="sm"
          variant="primary"
          :is-loading="isBusy"
          :disabled="!draft.label.trim()"
          @click="addField"
        >
          {{ t('KANBAN.CUSTOM_FIELDS.ADD') }}
        </Button>
      </div>
      <input
        v-if="isDropdown"
        v-model="draft.choices"
        type="text"
        class="kanban-cf-editor-input mt-2 w-full"
        :placeholder="t('KANBAN.CUSTOM_FIELDS.CHOICES_PLACEHOLDER')"
      />
    </div>
  </div>
</template>

<style scoped>
.kanban-cf-editor-input {
  border-radius: 0.5rem;
  border: 1px solid var(--color-border-weak, rgba(0, 0, 0, 0.1));
  background-color: var(--color-background, #fff);
  padding: 0.3rem 0.5rem;
  font-size: 12px;
  line-height: 1.2;
  color: inherit;
}
.kanban-cf-editor-input:focus {
  outline: none;
  border-color: var(--color-woot, #1f93ff);
}
</style>
