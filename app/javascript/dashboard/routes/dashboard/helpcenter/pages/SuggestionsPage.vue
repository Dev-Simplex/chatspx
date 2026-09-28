<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import SuggestionsAPI from 'dashboard/api/suggestions';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const MAX_MEDIA_MB = 100;
const MAX_CONTENT = 5000;

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const currentAccount = useMapGetter('getCurrentAccount');

const content = ref('');
const media = ref(null);
const mediaInput = ref(null);
const sending = ref(false);
const loading = ref(false);
const suggestions = ref([]);
const errorMessage = ref('');

const authorLine = computed(() =>
  t('SUGGESTIONS.FORM.AUTHOR', {
    name: currentUser.value?.name || '',
    company: currentAccount.value?.name || '',
  })
);

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
  } catch (error) {
    useAlert(t('SUGGESTIONS.LIST.ERROR'));
  } finally {
    loading.value = false;
  }
};

// Foto ou vídeo, até 100 MB — a mesma regra que o modelo aplica no servidor.
const onFileChange = event => {
  const [file] = event.target.files || [];
  errorMessage.value = '';
  if (!file) {
    media.value = null;
    return;
  }
  if (!/^(image|video)\//.test(file.type)) {
    errorMessage.value = t('SUGGESTIONS.FORM.ERROR_TYPE');
    event.target.value = '';
    return;
  }
  if (file.size > MAX_MEDIA_MB * 1024 * 1024) {
    errorMessage.value = t('SUGGESTIONS.FORM.ERROR_SIZE', {
      limit: MAX_MEDIA_MB,
    });
    event.target.value = '';
    return;
  }
  media.value = file;
};

const removeMedia = () => {
  media.value = null;
  if (mediaInput.value) mediaInput.value.value = '';
};

const submit = async () => {
  errorMessage.value = '';
  if (!content.value.trim()) {
    errorMessage.value = t('SUGGESTIONS.FORM.ERROR_EMPTY');
    return;
  }

  sending.value = true;
  try {
    await SuggestionsAPI.create({ content: content.value, media: media.value });
    content.value = '';
    removeMedia();
    useAlert(t('SUGGESTIONS.FORM.SUCCESS'));
    await loadSuggestions();
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error || t('SUGGESTIONS.FORM.ERROR_GENERIC');
  } finally {
    sending.value = false;
  }
};

onMounted(loadSuggestions);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div class="w-full max-w-2xl px-4 py-6 mx-auto sm:px-6">
      <h1 class="text-heading-1 text-n-slate-12">
        {{ $t('SUGGESTIONS.TITLE') }}
      </h1>
      <p class="mt-2 mb-0 text-body-main text-n-slate-11">
        {{ $t('SUGGESTIONS.DESCRIPTION') }}
      </p>

      <div class="p-4 mt-6 border rounded-xl border-n-weak bg-n-solid-1">
        <p class="mb-3 text-sm text-n-slate-11">{{ authorLine }}</p>

        <TextArea
          v-model="content"
          :placeholder="$t('SUGGESTIONS.FORM.PLACEHOLDER')"
          :max-length="MAX_CONTENT"
          auto-height
          min-height="7rem"
          class="w-full"
        />

        <div
          class="flex flex-col gap-3 mt-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex items-center gap-2 min-w-0">
            <input
              ref="mediaInput"
              type="file"
              accept="image/*,video/*"
              class="hidden"
              data-testid="suggestion-media"
              @change="onFileChange"
            />
            <Button
              :label="$t('SUGGESTIONS.FORM.ATTACH')"
              icon="i-lucide-paperclip"
              size="sm"
              variant="faded"
              color="slate"
              class="w-full sm:w-auto whitespace-nowrap"
              @click="mediaInput?.click()"
            />
            <span
              v-if="media"
              class="flex items-center gap-1 min-w-0 text-sm text-n-slate-11"
            >
              <span class="truncate">{{ media.name }}</span>
              <button
                type="button"
                class="flex-shrink-0 text-n-slate-10 hover:text-n-slate-12"
                :aria-label="$t('SUGGESTIONS.FORM.REMOVE_ATTACH')"
                @click="removeMedia"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </span>
          </div>
          <Button
            :label="$t('SUGGESTIONS.FORM.SUBMIT')"
            size="sm"
            :is-loading="sending"
            class="w-full sm:w-auto whitespace-nowrap"
            data-testid="suggestion-submit"
            @click="submit"
          />
        </div>

        <p v-if="errorMessage" class="mt-3 mb-0 text-sm text-n-ruby-11">
          {{ errorMessage }}
        </p>
      </div>

      <h2 class="mt-8 text-heading-2 text-n-slate-12">
        {{ $t('SUGGESTIONS.LIST.TITLE') }}
      </h2>

      <p
        v-if="!loading && !suggestions.length"
        class="mt-3 mb-0 text-body-main text-n-slate-11"
      >
        {{ $t('SUGGESTIONS.LIST.EMPTY') }}
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
