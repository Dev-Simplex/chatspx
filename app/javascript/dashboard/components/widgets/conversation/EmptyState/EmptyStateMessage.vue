<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

defineProps({
  message: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  showCta: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const globalConfig = useMapGetter('globalConfig/get');

const installationName = computed(() => {
  return globalConfig.value?.installationName || 'Chatwoot';
});

const logoUrl = computed(() => {
  return globalConfig.value?.logoThumbnail || globalConfig.value?.logo || '/brand-assets/logo_thumbnail.svg';
});

const logoVisible = ref(true);

function openNewConversation() {
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
}
</script>

<template>
  <div
    class="relative flex flex-col items-center justify-center h-full w-full px-8 py-16 text-center"
  >
    <div class="flex flex-col items-center max-w-md">
      <!-- Logo with subtle float animation -->
      <div v-if="logoVisible" class="mb-8 animate-float-gentle">
        <img
          :src="logoUrl"
          alt=""
          class="size-20 drop-shadow-sm"
          @error="logoVisible = false"
        />
      </div>

      <h3 class="text-2xl font-semibold text-n-slate-12">
        {{ installationName }}
      </h3>

      <p class="mt-3 text-sm text-center text-n-slate-10 max-w-sm leading-relaxed">
        {{ message }}
      </p>

      <p
        v-if="description"
        class="mt-1 text-sm text-center text-n-slate-10 max-w-sm"
      >
        {{ description }}
      </p>

      <button
        v-if="showCta"
        class="flex items-center gap-2 mt-8 px-6 h-10 rounded-full bg-n-brand text-white font-medium text-sm hover:bg-[#1FB85A] transition-colors active:scale-[0.97]"
        @click="openNewConversation"
      >
        <span class="i-lucide-message-square-plus size-4" />
        {{ t('CONVERSATION.EMPTY_STATE.NEW_CONVERSATION') }}
      </button>
    </div>

    <div
      class="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-1.5"
    >
      <span class="i-lucide-lock size-3 text-n-slate-9" />
      <span class="text-xs text-n-slate-9">
        {{ t('CONVERSATION.EMPTY_STATE.ENCRYPTION_NOTICE') }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.animate-float-gentle {
  animation: float-gentle 3s ease-in-out infinite;
}
@keyframes float-gentle {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-8px); }
}
</style>
