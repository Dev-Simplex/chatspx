<script setup>
import { ref, computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const showGallery = ref(false);
const shouldLoadVideo = ref(false);

const { filteredCurrentChatAttachments } = useMessageContext();

const videoSource = computed(() => {
  return shouldLoadVideo.value ? props.attachment.dataUrl : '';
});

const hasThumbnail = computed(() => {
  return Boolean(props.attachment.thumbUrl);
});

const videoPoster = computed(() => {
  return props.attachment.thumbUrl || undefined;
});

const loadVideo = () => {
  if (shouldLoadVideo.value) return;
  shouldLoadVideo.value = true;
};
</script>

<template>
  <div
    class="size-[72px] overflow-hidden contain-content rounded-xl cursor-pointer relative group"
    @pointerenter="loadVideo"
    @pointerdown="loadVideo"
    @touchstart.passive="loadVideo"
    @focusin="loadVideo"
    @click="showGallery = true"
  >
    <img
      v-if="hasThumbnail"
      :src="attachment.thumbUrl"
      class="w-full h-full object-cover skip-context-menu"
    />
    <video
      v-else
      preload="none"
      :poster="videoPoster"
      :src="videoSource"
      class="w-full h-full object-cover"
      muted
      playsInline
      @pointerenter="loadVideo"
      @pointerdown="loadVideo"
      @touchstart.passive="loadVideo"
      @focus="loadVideo"
    />
    <div
      class="absolute w-full h-full inset-0 p-1 flex items-center justify-center"
    >
      <div
        class="size-7 bg-n-slate-1/60 backdrop-blur-sm rounded-full overflow-hidden shadow-[0_5px_15px_rgba(0,0,0,0.4)]"
      >
        <Icon
          icon="i-teenyicons-play-small-solid"
          class="size-7 text-n-slate-12/80 backdrop-blur"
        />
      </div>
    </div>
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
