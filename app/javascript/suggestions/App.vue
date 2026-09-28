<script setup>
// SUG-02: formulario publico de sugestoes. Qualquer pessoa, sem login, manda nome, empresa,
// sugestao e foto/video. O caso principal e o celular (link aberto pelo WhatsApp).
import { reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const MAX_MEDIA_MB = 100;
const MAX_CONTENT = 5000;

const { t } = useI18n();
const { LOGO_THUMBNAIL: logo, INSTALLATION_NAME: installationName } =
  window.globalConfig || {};

const form = reactive({ name: '', company: '', content: '', website: '' });
const media = ref(null);
const mediaInput = ref(null);
const errors = reactive({});
const errorMessage = ref('');
const sending = ref(false);
const progress = ref(0);
const sent = ref(false);

const clearMedia = () => {
  media.value = null;
  if (mediaInput.value) mediaInput.value.value = '';
};

// Foto ou video, ate 100 MB: a mesma regra que o modelo aplica no servidor.
const onFileChange = event => {
  const [file] = event.target.files || [];
  errors.media = '';
  if (!file) return clearMedia();
  if (!/^(image|video)\//.test(file.type)) {
    errors.media = t('SUGGESTIONS_FORM.ERROR_TYPE');
    return clearMedia();
  }
  if (file.size > MAX_MEDIA_MB * 1024 * 1024) {
    errors.media = t('SUGGESTIONS_FORM.ERROR_SIZE', { limit: MAX_MEDIA_MB });
    return clearMedia();
  }
  media.value = file;
  return null;
};

const validate = () => {
  ['name', 'company', 'content'].forEach(field => {
    errors[field] = form[field].trim() ? '' : t('SUGGESTIONS_FORM.REQUIRED');
  });
  return !errors.name && !errors.company && !errors.content;
};

const submit = async () => {
  errorMessage.value = '';
  if (!validate()) return;

  const data = new FormData();
  Object.entries(form).forEach(([key, value]) => data.append(key, value));
  if (media.value) data.append('media', media.value);

  sending.value = true;
  progress.value = 0;
  try {
    await axios.post('/public/api/v1/suggestions', data, {
      onUploadProgress: ({ loaded, total }) => {
        if (total) progress.value = Math.round((loaded / total) * 100);
      },
    });
    sent.value = true;
  } catch (error) {
    const status = error?.response?.status;
    if (status === 429) {
      errorMessage.value = t('SUGGESTIONS_FORM.ERROR_TOO_MANY');
    } else {
      errorMessage.value =
        (status === 422 && error.response.data?.error) ||
        t('SUGGESTIONS_FORM.ERROR_GENERIC');
    }
  } finally {
    sending.value = false;
  }
};

const sendAnother = () => {
  Object.assign(form, { name: '', company: '', content: '', website: '' });
  Object.keys(errors).forEach(key => {
    errors[key] = '';
  });
  clearMedia();
  sent.value = false;
};

const inputClass =
  'w-full px-3 py-2.5 text-base border rounded-lg bg-n-solid-1 text-n-slate-12 border-n-weak outline-none focus:border-n-brand focus:ring-2 focus:ring-n-brand/20';
</script>

<template>
  <div class="min-h-screen bg-n-background sm:py-10">
    <main
      class="w-full max-w-xl px-4 py-6 mx-auto sm:px-8 sm:py-8 sm:border sm:shadow-lg sm:rounded-2xl sm:border-n-weak sm:bg-n-solid-1"
    >
      <header class="flex items-center gap-3 mb-6">
        <img v-if="logo" :src="logo" alt="" class="object-contain size-9" />
        <span class="text-base font-semibold text-n-slate-12">
          {{ installationName }}
        </span>
      </header>

      <section v-if="sent" class="py-10 text-center">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('SUGGESTIONS_FORM.THANKS_TITLE') }}
        </h1>
        <p class="mt-2 text-n-slate-11">
          {{ t('SUGGESTIONS_FORM.THANKS_TEXT') }}
        </p>
        <button
          type="button"
          class="w-full px-5 py-3 mt-6 font-medium text-white rounded-lg sm:w-auto bg-n-brand"
          @click="sendAnother"
        >
          {{ t('SUGGESTIONS_FORM.SEND_ANOTHER') }}
        </button>
      </section>

      <form v-else novalidate @submit.prevent="submit">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ t('SUGGESTIONS_FORM.TITLE') }}
        </h1>
        <p class="mt-2 mb-6 text-n-slate-11">
          {{ t('SUGGESTIONS_FORM.DESCRIPTION') }}
        </p>

        <!-- Honeypot: pessoa nao ve nem alcanca pelo Tab; bot preenche e o servidor descarta. -->
        <input
          v-model="form.website"
          type="text"
          name="website"
          class="hidden"
          tabindex="-1"
          autocomplete="off"
        />

        <label class="block mb-4">
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('SUGGESTIONS_FORM.NAME') }} *
          </span>
          <input
            v-model="form.name"
            type="text"
            autocomplete="name"
            :class="inputClass"
          />
          <span v-if="errors.name" class="block mt-1 text-sm text-n-ruby-11">
            {{ errors.name }}
          </span>
        </label>

        <label class="block mb-4">
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('SUGGESTIONS_FORM.COMPANY') }} *
          </span>
          <input
            v-model="form.company"
            type="text"
            autocomplete="organization"
            :class="inputClass"
          />
          <span v-if="errors.company" class="block mt-1 text-sm text-n-ruby-11">
            {{ errors.company }}
          </span>
        </label>

        <label class="block mb-4">
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('SUGGESTIONS_FORM.CONTENT') }} *
          </span>
          <textarea
            v-model="form.content"
            rows="5"
            :maxlength="MAX_CONTENT"
            :placeholder="t('SUGGESTIONS_FORM.CONTENT_PLACEHOLDER')"
            :class="inputClass"
          />
          <span v-if="errors.content" class="block mt-1 text-sm text-n-ruby-11">
            {{ errors.content }}
          </span>
        </label>

        <div class="mb-6">
          <span class="block mb-1 text-sm font-medium text-n-slate-12">
            {{ t('SUGGESTIONS_FORM.MEDIA') }}
          </span>
          <input
            ref="mediaInput"
            type="file"
            accept="image/*,video/*"
            class="block w-full text-sm text-n-slate-11 file:me-3 file:px-3 file:py-2 file:border-0 file:rounded-lg file:bg-n-alpha-2 file:text-n-slate-12"
            @change="onFileChange"
          />
          <div
            v-if="media"
            class="flex items-center justify-between gap-2 mt-2 text-sm text-n-slate-11"
          >
            <span class="truncate">{{ media.name }}</span>
            <button
              type="button"
              class="flex-shrink-0 underline"
              @click="clearMedia"
            >
              {{ t('SUGGESTIONS_FORM.MEDIA_REMOVE') }}
            </button>
          </div>
          <span v-else class="block mt-1 text-xs text-n-slate-10">
            {{ t('SUGGESTIONS_FORM.MEDIA_HINT', { limit: MAX_MEDIA_MB }) }}
          </span>
          <span v-if="errors.media" class="block mt-1 text-sm text-n-ruby-11">
            {{ errors.media }}
          </span>
        </div>

        <p v-if="errorMessage" class="mb-4 text-sm text-n-ruby-11">
          {{ errorMessage }}
        </p>

        <button
          type="submit"
          :disabled="sending"
          class="w-full px-5 py-3 font-medium text-white rounded-lg sm:w-auto bg-n-brand disabled:opacity-60"
        >
          {{
            sending
              ? t('SUGGESTIONS_FORM.SENDING', { progress })
              : t('SUGGESTIONS_FORM.SUBMIT')
          }}
        </button>
      </form>
    </main>
  </div>
</template>

<style lang="scss">
@import 'survey/assets/scss/woot.scss';
</style>
