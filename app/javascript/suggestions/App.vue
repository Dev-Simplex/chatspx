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

// Mesma paleta da pagina do Chat Interno (/chat-interno.html): preto, vidro, verde #2dc46f.
const inputClass =
  'w-full px-3.5 py-3 text-base rounded-xl border border-white/10 bg-white/[0.035] text-white placeholder:text-white/40 outline-none transition focus:border-[#2dc46f]/70 focus:ring-2 focus:ring-[#2dc46f]/20';
</script>

<template>
  <div
    class="min-h-screen bg-black text-white font-['Geist',ui-sans-serif,system-ui,sans-serif] bg-[radial-gradient(ellipse_90%_55%_at_50%_-10%,rgba(45,196,111,0.35),transparent_70%)]"
  >
    <div class="w-full max-w-xl px-4 pt-6 pb-12 mx-auto sm:pt-10">
      <header class="flex items-center gap-3 mb-10">
        <img v-if="logo" :src="logo" alt="" class="object-contain size-9" />
        <span class="text-lg font-semibold tracking-tight">
          {{ installationName }}
        </span>
      </header>

      <section v-if="sent" class="py-12 text-center">
        <h1 class="text-5xl font-semibold tracking-tight text-[#7ff5b5]">
          {{ t('SUGGESTIONS_FORM.THANKS_TITLE') }}
        </h1>
        <p class="mt-4 text-lg leading-relaxed text-white/70">
          {{ t('SUGGESTIONS_FORM.THANKS_TEXT') }}
        </p>
        <button
          type="button"
          class="w-full px-6 py-3.5 mt-8 font-semibold rounded-xl sm:w-auto bg-[#2dc46f] text-[#04130a] transition hover:bg-[#5ff0a3]"
          @click="sendAnother"
        >
          {{ t('SUGGESTIONS_FORM.SEND_ANOTHER') }}
        </button>
      </section>

      <template v-else>
        <span
          class="inline-flex items-center gap-2 px-3 py-1 text-sm border rounded-full border-[#2dc46f]/40 bg-[#2dc46f]/10 text-[#8ff5bd]"
        >
          <span class="rounded-full size-1.5 bg-[#2dc46f]" />
          {{ t('SUGGESTIONS_FORM.BADGE') }}
        </span>
        <h1
          class="mt-5 text-4xl font-semibold leading-[1.05] tracking-tight sm:text-5xl"
        >
          {{ t('SUGGESTIONS_FORM.TITLE') }}
          <span class="block text-[#7ff5b5]">
            {{ t('SUGGESTIONS_FORM.TITLE_ACCENT') }}
          </span>
        </h1>
        <p class="mt-4 mb-8 text-lg leading-relaxed text-white/70">
          {{ t('SUGGESTIONS_FORM.DESCRIPTION') }}
        </p>

        <form
          novalidate
          class="p-4 border sm:p-6 rounded-2xl border-white/10 bg-white/[0.035] backdrop-blur"
          @submit.prevent="submit"
        >
          <!-- Honeypot: pessoa nao ve nem alcanca pelo Tab; bot preenche e o servidor descarta. -->
          <input
            v-model="form.website"
            type="text"
            name="website"
            class="hidden"
            tabindex="-1"
            autocomplete="off"
          />

          <label class="block mb-5">
            <span class="block mb-1.5 text-sm font-medium text-white/80">
              {{ t('SUGGESTIONS_FORM.NAME') }}
            </span>
            <input
              v-model="form.name"
              type="text"
              autocomplete="name"
              :class="inputClass"
            />
            <span
              v-if="errors.name"
              class="block mt-1.5 text-sm text-[#ff8a8a]"
            >
              {{ errors.name }}
            </span>
          </label>

          <label class="block mb-5">
            <span class="block mb-1.5 text-sm font-medium text-white/80">
              {{ t('SUGGESTIONS_FORM.COMPANY') }}
            </span>
            <input
              v-model="form.company"
              type="text"
              autocomplete="organization"
              :class="inputClass"
            />
            <span
              v-if="errors.company"
              class="block mt-1.5 text-sm text-[#ff8a8a]"
            >
              {{ errors.company }}
            </span>
          </label>

          <label class="block mb-5">
            <span class="block mb-1.5 text-sm font-medium text-white/80">
              {{ t('SUGGESTIONS_FORM.CONTENT') }}
            </span>
            <textarea
              v-model="form.content"
              rows="5"
              :maxlength="MAX_CONTENT"
              :placeholder="t('SUGGESTIONS_FORM.CONTENT_PLACEHOLDER')"
              :class="inputClass"
            />
            <span
              v-if="errors.content"
              class="block mt-1.5 text-sm text-[#ff8a8a]"
            >
              {{ errors.content }}
            </span>
          </label>

          <div class="mb-6">
            <span class="block mb-1.5 text-sm font-medium text-white/80">
              {{ t('SUGGESTIONS_FORM.MEDIA') }}
            </span>
            <input
              ref="mediaInput"
              type="file"
              accept="image/*,video/*"
              class="block w-full text-sm text-white/60 file:me-3 file:px-4 file:py-2.5 file:rounded-xl file:border file:border-white/15 file:bg-white/[0.07] file:text-white file:font-medium"
              @change="onFileChange"
            />
            <div
              v-if="media"
              class="flex items-center justify-between gap-2 mt-2 text-sm text-white/70"
            >
              <span class="truncate">{{ media.name }}</span>
              <button
                type="button"
                class="flex-shrink-0 underline text-[#8ff5bd]"
                @click="clearMedia"
              >
                {{ t('SUGGESTIONS_FORM.MEDIA_REMOVE') }}
              </button>
            </div>
            <span v-else class="block mt-1.5 text-xs text-white/45">
              {{ t('SUGGESTIONS_FORM.MEDIA_HINT', { limit: MAX_MEDIA_MB }) }}
            </span>
            <span
              v-if="errors.media"
              class="block mt-1.5 text-sm text-[#ff8a8a]"
            >
              {{ errors.media }}
            </span>
          </div>

          <p v-if="errorMessage" class="mb-4 text-sm text-[#ff8a8a]">
            {{ errorMessage }}
          </p>

          <button
            type="submit"
            :disabled="sending"
            class="w-full px-6 py-3.5 font-semibold rounded-xl bg-[#2dc46f] text-[#04130a] transition hover:bg-[#5ff0a3] disabled:opacity-60"
          >
            {{
              sending
                ? t('SUGGESTIONS_FORM.SENDING', { progress })
                : t('SUGGESTIONS_FORM.SUBMIT')
            }}
          </button>
        </form>
      </template>
    </div>
  </div>
</template>

<style lang="scss">
@import 'survey/assets/scss/woot.scss';
</style>
