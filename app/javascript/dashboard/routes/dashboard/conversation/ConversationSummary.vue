<script setup>
import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const store = useStore();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

const customAttributes = computed(
  () => currentChat.value?.custom_attributes || {}
);
const aiSummary = computed(
  () => customAttributes.value.resumo_atendimento_ia || ''
);
const humanSummary = computed(
  () => customAttributes.value.resumo_atendimento_humano || ''
);

const editingKey = ref(null);
const draft = ref('');
const saving = ref(false);

const startEdit = (key, current) => {
  editingKey.value = key;
  draft.value = current;
};

const cancelEdit = () => {
  editingKey.value = null;
  draft.value = '';
};

const save = async key => {
  saving.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...customAttributes.value,
        [key]: draft.value.trim(),
      },
    });
    editingKey.value = null;
    draft.value = '';
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.SUMMARY.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2 px-3 py-3 border-b border-n-weak/50">
    <!-- Resumo da IA (realçado) -->
    <div class="px-3 py-2.5 border rounded-lg border-n-brand/30 bg-n-brand/5">
      <div class="flex items-center justify-between mb-1">
        <div class="flex items-center gap-1.5">
          <span class="i-lucide-sparkles size-3.5 text-n-brand" />
          <span class="text-xs font-semibold text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.AI_TITLE') }}
          </span>
        </div>
        <button
          v-if="editingKey !== 'resumo_atendimento_ia'"
          class="flex items-center justify-center rounded size-5 text-n-slate-10 hover:bg-n-slate-3 hover:text-n-slate-12"
          :title="$t('CONVERSATION_SIDEBAR.SUMMARY.EDIT')"
          @click="startEdit('resumo_atendimento_ia', aiSummary)"
        >
          <span class="i-lucide-pencil size-3" />
        </button>
      </div>
      <template v-if="editingKey === 'resumo_atendimento_ia'">
        <textarea
          v-model="draft"
          rows="4"
          class="w-full px-2 py-1.5 text-xs border rounded resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
        <div class="flex items-center justify-end gap-3 mt-1.5">
          <button
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="cancelEdit"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.CANCEL') }}
          </button>
          <button
            class="text-xs font-medium text-n-brand disabled:opacity-50"
            :disabled="saving"
            @click="save('resumo_atendimento_ia')"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.SAVE') }}
          </button>
        </div>
      </template>
      <p
        v-else-if="aiSummary"
        class="text-xs leading-relaxed text-n-slate-12 whitespace-pre-line"
      >
        {{ aiSummary }}
      </p>
      <p v-else class="text-xs italic text-n-slate-10">
        {{ $t('CONVERSATION_SIDEBAR.SUMMARY.AI_EMPTY') }}
      </p>
    </div>

    <!-- Resumo do humano (editável) -->
    <div class="px-3 py-2.5 border rounded-lg border-n-weak bg-n-solid-2">
      <div class="flex items-center justify-between mb-1">
        <div class="flex items-center gap-1.5">
          <span class="i-lucide-user-round size-3.5 text-n-slate-11" />
          <span class="text-xs font-semibold text-n-slate-12">
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.HUMAN_TITLE') }}
          </span>
        </div>
        <button
          v-if="editingKey !== 'resumo_atendimento_humano'"
          class="flex items-center justify-center rounded size-5 text-n-slate-10 hover:bg-n-slate-3 hover:text-n-slate-12"
          :title="$t('CONVERSATION_SIDEBAR.SUMMARY.EDIT')"
          @click="startEdit('resumo_atendimento_humano', humanSummary)"
        >
          <span class="i-lucide-pencil size-3" />
        </button>
      </div>
      <template v-if="editingKey === 'resumo_atendimento_humano'">
        <textarea
          v-model="draft"
          rows="4"
          class="w-full px-2 py-1.5 text-xs border rounded resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
        <div class="flex items-center justify-end gap-3 mt-1.5">
          <button
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="cancelEdit"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.CANCEL') }}
          </button>
          <button
            class="text-xs font-medium text-n-brand disabled:opacity-50"
            :disabled="saving"
            @click="save('resumo_atendimento_humano')"
          >
            {{ $t('CONVERSATION_SIDEBAR.SUMMARY.SAVE') }}
          </button>
        </div>
      </template>
      <p
        v-else-if="humanSummary"
        class="text-xs leading-relaxed text-n-slate-12 whitespace-pre-line"
      >
        {{ humanSummary }}
      </p>
      <p v-else class="text-xs italic text-n-slate-10">
        {{ $t('CONVERSATION_SIDEBAR.SUMMARY.HUMAN_EMPTY') }}
      </p>
    </div>
  </div>
</template>
