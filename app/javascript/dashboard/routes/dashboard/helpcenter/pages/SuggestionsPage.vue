<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import SuggestionsAPI from 'dashboard/api/suggestions';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const MAX_MEDIA_MB = 100;
const MAX_CONTENT = 5000;

const { t } = useI18n();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const currentAccount = useMapGetter('getCurrentAccount');

const content = ref('');
const media = ref(null);
const mediaInput = ref(null);
const sending = ref(false);
const errorMessage = ref('');

// Montado do domínio aberto: cada instalação tem o seu (nicolas.chatspx.app,
// chat.simplexsolucoes.com.br, o de cada cliente), então nada de URL fixa.
const publicLink = computed(() => `${window.location.origin}/sugestoes`);

const copyPublicLink = async () => {
  await copyTextToClipboard(publicLink.value);
  useAlert(t('SUGGESTIONS.PUBLIC_LINK.COPIED'));
};

const authorLine = computed(() =>
  t('SUGGESTIONS.FORM.AUTHOR', {
    name: currentUser.value?.name || '',
    company: currentAccount.value?.name || '',
  })
);

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
    // A sugestão aparece em "Sugestões enviadas" — leva a pessoa até lá.
    router.push({ name: 'suggestions_sent' });
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.error || t('SUGGESTIONS.FORM.ERROR_GENERIC');
  } finally {
    sending.value = false;
  }
};
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

      <div class="p-4 mt-4 border rounded-xl border-n-weak bg-n-solid-1">
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
          <Button
            :label="$t('SUGGESTIONS.PUBLIC_LINK.COPY')"
            icon="i-lucide-copy"
            variant="ghost"
            color="slate"
            size="sm"
            class="w-full sm:w-auto whitespace-nowrap"
            @click="copyPublicLink"
          />
        </div>
        <p class="mt-2 mb-0 text-sm text-n-slate-11">
          {{ $t('SUGGESTIONS.PUBLIC_LINK.HINT') }}
        </p>
      </div>
    </div>
  </div>
</template>
