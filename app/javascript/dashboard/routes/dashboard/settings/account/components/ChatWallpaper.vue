<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AccountAPI from 'dashboard/api/account';
import SectionLayout from './SectionLayout.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_BYTES = 5 * 1024 * 1024;

const tab = ref('url'); // 'url' | 'upload'
const wallpaperUrl = ref('');
const fileInputRef = ref(null);
const isUploading = ref(false);

const previewUrl = computed(() => wallpaperUrl.value || '');

watch(
  currentAccount,
  () => {
    wallpaperUrl.value =
      currentAccount.value?.settings?.chat_wallpaper_url || '';
  },
  { deep: true, immediate: true }
);

const saveUrl = async () => {
  try {
    await updateAccount({ chat_wallpaper_url: wallpaperUrl.value || '' });
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.ERROR'));
  }
};

const reset = async () => {
  try {
    await AccountAPI.removeChatWallpaper();
    wallpaperUrl.value = '';
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.ERROR'));
  }
};

const triggerUpload = () => fileInputRef.value?.click();

const onFileSelected = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (!ALLOWED_TYPES.includes(file.type)) {
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.UPLOAD.INVALID_TYPE'));
    event.target.value = '';
    return;
  }
  if (file.size > MAX_BYTES) {
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.UPLOAD.TOO_LARGE'));
    event.target.value = '';
    return;
  }
  isUploading.value = true;
  try {
    const { data } = await AccountAPI.uploadChatWallpaper(file);
    wallpaperUrl.value = data?.url || '';
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.API.ERROR'));
  } finally {
    isUploading.value = false;
    event.target.value = '';
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.NOTE')"
    with-border
  >
    <div class="flex flex-col gap-3 max-w-xl">
      <div class="flex gap-2 border-b border-n-weak">
        <button
          type="button"
          class="px-3 py-1.5 text-sm border-b-2 -mb-px transition-colors"
          :class="
            tab === 'url'
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11'
          "
          @click="tab = 'url'"
        >
          {{ t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.TABS.URL') }}
        </button>
        <button
          type="button"
          class="px-3 py-1.5 text-sm border-b-2 -mb-px transition-colors"
          :class="
            tab === 'upload'
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11'
          "
          @click="tab = 'upload'"
        >
          {{ t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.TABS.UPLOAD') }}
        </button>
      </div>

      <div v-if="tab === 'url'" class="flex flex-col gap-2">
        <NextInput
          v-model="wallpaperUrl"
          type="url"
          :placeholder="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.PLACEHOLDER')"
        />
        <div class="flex gap-2">
          <NextButton
            :label="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.SAVE')"
            variant="solid"
            color="brand"
            @click="saveUrl"
          />
          <NextButton
            :label="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.RESET')"
            variant="ghost"
            color="slate"
            @click="reset"
          />
        </div>
      </div>

      <div v-else class="flex flex-col gap-2">
        <input
          ref="fileInputRef"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          class="hidden"
          @change="onFileSelected"
        />
        <p class="text-xs text-n-slate-11">
          {{ t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.UPLOAD.HINT') }}
        </p>
        <div class="flex gap-2">
          <NextButton
            :label="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.UPLOAD.BUTTON')"
            variant="solid"
            color="brand"
            :is-loading="isUploading"
            @click="triggerUpload"
          />
          <NextButton
            v-if="previewUrl"
            :label="t('GENERAL_SETTINGS.FORM.CHAT_WALLPAPER.RESET')"
            variant="ghost"
            color="slate"
            @click="reset"
          />
        </div>
      </div>

      <div
        v-if="previewUrl"
        class="rounded-md border border-n-weak overflow-hidden h-32 bg-cover bg-center"
        :style="{ backgroundImage: `url('${previewUrl}')` }"
      />
    </div>
  </SectionLayout>
</template>
