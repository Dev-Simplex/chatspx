<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import EvalDashboardAPI from 'dashboard/api/captain/evalDashboard';
import NextButton from 'dashboard/components-next/button/Button.vue';

// F4.2 (Eval humano): a conversa é perpétua, mas o Eval julga por EPISÓDIO.
// Este modal lista os episódios da conversa pro gestor escolher QUAL atendimento
// está avaliando — a observação vira nota #eval ancorada explicitamente nele.
const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  currentChat: {
    type: Object,
    required: true,
  },
  // Âncora opcional vinda do menu ⋮ de uma mensagem: { messageId, trecho }.
  // Pré-seleciona o episódio que contém a mensagem e cita o trecho na observação.
  anchor: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['cancel']);

const { t } = useI18n();

const loading = ref(true);
const episodes = ref([]);
const selectedId = ref(null);
const texto = ref('');
const submitting = ref(false);

const fmt = iso => {
  if (!iso) return '';
  return new Date(iso).toLocaleString(undefined, {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const episodeContains = (ep, messageId) => {
  if (!ep.first_message_id) return false;
  if (messageId < ep.first_message_id) return false;
  return !ep.last_message_id || messageId <= ep.last_message_id;
};

onMounted(async () => {
  try {
    const { data } = await EvalDashboardAPI.conversationEpisodes(
      props.currentChat.id
    );
    episodes.value = data.episodes || [];
    selectedId.value = episodes.value[0]?.id || null;
    if (props.anchor?.messageId) {
      const target = episodes.value.find(ep =>
        episodeContains(ep, props.anchor.messageId)
      );
      if (target) selectedId.value = target.id;
      if (props.anchor.trecho) texto.value = `“${props.anchor.trecho}” — `;
    }
  } catch (e) {
    episodes.value = [];
  } finally {
    loading.value = false;
  }
});

const onCancel = () => emit('cancel');

const onSubmit = async () => {
  if (!selectedId.value || !texto.value.trim() || submitting.value) return;
  submitting.value = true;
  try {
    const { data } = await EvalDashboardAPI.annotate({
      conversationDisplayId: props.currentChat.id,
      episodeId: selectedId.value,
      texto: texto.value.trim(),
    });
    useAlert(
      data.pending
        ? t('EVALUATE_EPISODE.SUCCESS_OPEN')
        : t('EVALUATE_EPISODE.SUCCESS')
    );
    emit('cancel');
  } catch (e) {
    useAlert(t('EVALUATE_EPISODE.ERROR'));
  } finally {
    submitting.value = false;
  }
};
</script>

<template>
  <woot-modal :show="show" :on-close="onCancel">
    <woot-modal-header
      :header-title="t('EVALUATE_EPISODE.TITLE')"
      :header-content="t('EVALUATE_EPISODE.DESC')"
    />
    <div class="flex flex-col gap-3 px-8 pt-2 pb-6">
      <div v-if="loading" class="py-6 text-sm text-center text-n-slate-10">
        {{ t('EVALUATE_EPISODE.LOADING') }}
      </div>
      <div
        v-else-if="!episodes.length"
        class="py-6 text-sm text-center text-n-slate-10"
      >
        {{ t('EVALUATE_EPISODE.NO_EPISODES') }}
      </div>
      <template v-else>
        <div class="flex overflow-y-auto flex-col gap-1.5 max-h-64">
          <label
            v-for="ep in episodes"
            :key="ep.id"
            class="flex gap-3 items-start p-3 rounded-xl border cursor-pointer"
            :class="
              selectedId === ep.id
                ? 'border-n-brand bg-n-brand/5'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
          >
            <input
              v-model="selectedId"
              type="radio"
              :value="ep.id"
              class="mt-1 shrink-0"
            />
            <span class="flex flex-col gap-0.5 min-w-0">
              <span class="text-sm font-semibold text-n-slate-12">
                {{ t('EVALUATE_EPISODE.EPISODE', { seq: ep.seq }) }}
                <span class="font-normal text-n-slate-11">
                  · {{ fmt(ep.started_at) }}
                  {{ ep.ended_at ? `→ ${fmt(ep.ended_at)}` : '' }}
                </span>
                <span
                  v-if="!ep.ended_at"
                  class="px-1.5 py-0.5 ml-1 text-[11px] font-semibold rounded-full bg-n-amber-9/15 text-n-amber-11"
                >
                  {{ t('EVALUATE_EPISODE.CURRENT') }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('EVALUATE_EPISODE.MESSAGES', { count: ep.mensagens }) }}
                <template v-if="ep.nota !== null && ep.nota !== undefined">
                  · {{ t('EVALUATE_EPISODE.NOTA', { nota: ep.nota }) }}
                </template>
                <template v-if="ep.anotacoes">
                  ·
                  {{ t('EVALUATE_EPISODE.ANNOTATED', { count: ep.anotacoes }) }}
                </template>
              </span>
              <span v-if="ep.resumo" class="text-xs truncate text-n-slate-10">
                {{ ep.resumo }}
              </span>
            </span>
          </label>
        </div>
        <textarea
          v-model="texto"
          rows="3"
          class="p-3 w-full text-sm rounded-xl border resize-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:outline-none"
          :placeholder="t('EVALUATE_EPISODE.PLACEHOLDER')"
        />
        <div class="flex gap-2 justify-end">
          <NextButton
            variant="ghost"
            color="slate"
            :label="t('EVALUATE_EPISODE.CANCEL')"
            @click="onCancel"
          />
          <NextButton
            :label="t('EVALUATE_EPISODE.SUBMIT')"
            :is-loading="submitting"
            :disabled="!selectedId || !texto.trim()"
            @click="onSubmit"
          />
        </div>
      </template>
    </div>
  </woot-modal>
</template>
