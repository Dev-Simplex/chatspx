<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  referral: { type: Object, required: true },
});

const { t } = useI18n();

const mediaUrl = computed(
  () => props.referral.image_url || props.referral.thumbnail_url
);
const hasMedia = computed(() => !!mediaUrl.value);
const hasContent = computed(
  () => !!(props.referral.headline || props.referral.body)
);
</script>

<template>
  <a
    :href="referral.source_url"
    target="_blank"
    rel="noopener noreferrer"
    class="block max-w-xs mb-1 rounded-xl overflow-hidden border border-n-strong bg-n-alpha-2 hover:bg-n-alpha-3 transition-colors"
  >
    <img
      v-if="hasMedia"
      :src="mediaUrl"
      :alt="referral.headline || ''"
      class="w-full aspect-video object-cover"
    />
    <div class="p-3">
      <p
        v-if="referral.headline"
        class="text-sm font-medium text-n-slate-12 mb-1 line-clamp-2"
      >
        {{ referral.headline }}
      </p>
      <p v-if="referral.body" class="text-xs text-n-slate-11 line-clamp-3">
        {{ referral.body }}
      </p>
      <p v-if="!hasContent" class="text-xs text-n-slate-11">
        {{ t('CONVERSATION.REFERRAL.OPEN_AD') }}
      </p>
      <div class="flex items-center gap-1.5 mt-2 text-xs text-n-iris-11">
        <Icon icon="i-lucide-megaphone" class="size-3.5" />
        {{ t('CONVERSATION.REFERRAL.FROM_AD') }}
      </div>
    </div>
  </a>
</template>
