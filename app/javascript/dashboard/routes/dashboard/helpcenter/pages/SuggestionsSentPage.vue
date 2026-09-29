<script setup>
// "Sugestões enviadas": a lista que ficava embaixo do formulário virou item próprio no menu.
// O alcance vem do backend (meta.all_account): admin da conta vê as de todos, com o autor.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import SuggestionsAPI from 'dashboard/api/suggestions';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';

const { t } = useI18n();

// Montado do domínio aberto: cada instalação tem o seu (nicolas.chatspx.app,
// chat.simplexsolucoes.com.br, o de cada cliente), então nada de URL fixa.
const publicLink = computed(() => `${window.location.origin}/sugestoes`);

const copyPublicLink = async () => {
  await copyTextToClipboard(publicLink.value);
  useAlert(t('SUGGESTIONS.PUBLIC_LINK.COPIED'));
};

const loading = ref(false);
const suggestions = ref([]);
const allAccount = ref(false);

// Mapa explícito: chave dinâmica de i18n some do bundle no build e o lint avisa disso.
const STATUS_LABELS = () => ({
  nova: t('SUGGESTIONS.STATUS.NOVA'),
  lida: t('SUGGESTIONS.STATUS.LIDA'),
  planejada: t('SUGGESTIONS.STATUS.PLANEJADA'),
  feita: t('SUGGESTIONS.STATUS.FEITA'),
});

const statusLabel = status => STATUS_LABELS()[status] || status;

const formatDate = timestamp =>
  new Date(timestamp * 1000).toLocaleDateString(undefined, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });

const loadSuggestions = async () => {
  loading.value = true;
  try {
    const { data } = await SuggestionsAPI.get();
    suggestions.value = data?.payload || [];
    allAccount.value = !!data?.meta?.all_account;
  } catch (error) {
    useAlert(t('SUGGESTIONS.LIST.ERROR'));
  } finally {
    loading.value = false;
  }
};

onMounted(loadSuggestions);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div class="w-full max-w-2xl px-4 py-6 mx-auto sm:px-6">
      <h1 class="text-heading-1 text-n-slate-12">
        {{
          allAccount
            ? $t('SUGGESTIONS.LIST.TITLE_ADMIN')
            : $t('SUGGESTIONS.LIST.TITLE')
        }}
      </h1>

      <div
        v-if="allAccount"
        class="p-4 mt-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center gap-2">
          <Icon
            icon="i-lucide-link"
            class="flex-shrink-0 size-4 text-n-slate-11"
          />
          <h2 class="mb-0 font-medium text-body-main text-n-slate-12">
            {{ $t('SUGGESTIONS.PUBLIC_LINK.TITLE') }}
          </h2>
        </div>
        <div class="flex flex-wrap items-center gap-2 mt-3">
          <span
            class="w-full min-w-0 px-3 py-2 text-sm break-all rounded-lg sm:flex-1 bg-n-alpha-2 text-n-slate-12"
          >
            {{ publicLink }}
          </span>
          <NextButton
            ghost
            sm
            slate
            icon="i-lucide-copy"
            :label="$t('SUGGESTIONS.PUBLIC_LINK.COPY')"
            @click="copyPublicLink"
          />
        </div>
        <p class="mt-2 mb-0 text-sm text-n-slate-11">
          {{ $t('SUGGESTIONS.PUBLIC_LINK.HINT') }}
        </p>
      </div>

      <p
        v-if="!loading && !suggestions.length"
        class="mt-3 mb-0 text-body-main text-n-slate-11"
      >
        {{
          allAccount
            ? $t('SUGGESTIONS.LIST.EMPTY_ADMIN')
            : $t('SUGGESTIONS.LIST.EMPTY')
        }}
      </p>

      <ul class="mt-3 mb-0 space-y-3 list-none">
        <li
          v-for="suggestion in suggestions"
          :key="suggestion.id"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center gap-2 justify-between">
            <span class="text-sm text-n-slate-11">
              {{ formatDate(suggestion.created_at) }}
              <span v-if="allAccount" class="ms-2 font-medium text-n-slate-12">
                {{ suggestion.name }}
              </span>
              <template v-if="suggestion.source === 'public_link'">
                <span class="ms-1 text-n-slate-11">{{
                  suggestion.company
                }}</span>
                <span
                  class="ms-2 px-2 py-0.5 text-xs rounded-md bg-n-teal-3 text-n-teal-11"
                >
                  {{ $t('SUGGESTIONS.LIST.SOURCE_LINK') }}
                </span>
              </template>
            </span>
            <span
              class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
            >
              {{ statusLabel(suggestion.status) }}
            </span>
          </div>
          <p
            class="mt-2 mb-0 break-words whitespace-pre-line text-body-main text-n-slate-12"
          >
            {{ suggestion.content }}
          </p>
          <a
            v-if="suggestion.media_url"
            :href="suggestion.media_url"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 mt-2 text-sm break-all text-n-blue-11 hover:underline"
          >
            <Icon icon="i-lucide-paperclip" class="flex-shrink-0 size-3.5" />
            {{ suggestion.media_filename }}
          </a>
        </li>
      </ul>
    </div>
  </div>
</template>
