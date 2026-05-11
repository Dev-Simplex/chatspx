<script setup>
import { computed, onBeforeUnmount, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import SenderAvatar from './SenderAvatar.vue';
import MediaThumb from './MediaThumb.vue';
import {
  useGroupedByDate,
  formatTime,
} from '../composables/useGroupedByDate.js';

const props = defineProps({
  items: { type: Array, required: true },
  selectedIds: { type: Set, required: true },
  isLoadingMore: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggleSelect',
  'open',
  'openConversation',
  'loadMore',
]);

const EAGER_LCP_COUNT = 6;

const { t } = useI18n();
const groups = useGroupedByDate(toRef(props, 'items'), t);
const sentinel = ref(null);
let observer = null;

const groupOffsets = computed(() => {
  const offsets = [];
  let total = 0;
  groups.value.forEach(group => {
    offsets.push(total);
    total += group.items.length;
  });
  return offsets;
});

const globalIndex = (groupIndex, localIndex) =>
  (groupOffsets.value[groupIndex] || 0) + localIndex;

onMounted(() => {
  if (!sentinel.value) return;
  observer = new IntersectionObserver(
    entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting && props.hasMore && !props.isLoadingMore) {
          emit('loadMore');
        }
      });
    },
    { rootMargin: '400px' }
  );
  observer.observe(sentinel.value);
});

onBeforeUnmount(() => {
  if (observer) observer.disconnect();
});
</script>

<template>
  <div>
    <section
      v-for="(group, groupIndex) in groups"
      :key="group.key"
      class="mb-10 last:mb-0"
    >
      <h3
        class="sticky -top-px z-20 -mx-6 sm:-mx-8 lg:-mx-10 px-6 sm:px-8 lg:px-10 py-3 mb-4 text-[13px] uppercase tracking-wider font-semibold text-n-slate-11 bg-n-background/95 dark:bg-n-solid-1/95 backdrop-blur"
      >
        {{ group.label }}
      </h3>

      <div class="grid gap-3 grid-cols-[repeat(auto-fill,minmax(180px,1fr))]">
        <article
          v-for="(item, index) in group.items"
          :key="item.id"
          class="group relative aspect-square overflow-hidden rounded-2xl bg-n-solid-2 dark:bg-n-solid-3 cursor-pointer ring-2 ring-transparent transition-all hover:ring-n-brand/30 [content-visibility:auto] [contain-intrinsic-size:0_220px]"
          :class="{
            '!ring-n-brand !ring-offset-2 !ring-offset-n-background dark:!ring-offset-n-solid-1':
              selectedIds.has(item.id),
          }"
          @click="$emit('open', item)"
        >
          <!-- Thumbnail -->
          <MediaThumb
            v-if="item.fileType !== 'video' && (item.thumbUrl || item.dataUrl)"
            :src="item.thumbUrl || item.dataUrl"
            :alt="item.filename || ''"
            :width="item.width || 400"
            :height="item.height || 400"
            :eager="globalIndex(groupIndex, index) < EAGER_LCP_COUNT"
            :high-priority="globalIndex(groupIndex, index) < EAGER_LCP_COUNT"
          />
          <div
            v-else-if="item.fileType === 'video'"
            class="relative w-full h-full"
          >
            <video
              :src="item.dataUrl"
              class="w-full h-full object-cover"
              preload="metadata"
              muted
            />
            <span
              class="absolute inset-0 flex items-center justify-center bg-black/30 group-hover:bg-black/40 transition-colors"
            >
              <span
                class="size-12 rounded-full bg-white/95 text-n-slate-12 flex items-center justify-center shadow-lg"
              >
                <span class="i-lucide-play size-5 ml-0.5" />
              </span>
            </span>
          </div>

          <!-- Gradient overlay sempre visível pra legibilidade do contato -->
          <div
            class="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/85 via-black/50 to-transparent pointer-events-none"
          />

          <!-- Info do contato (sempre visível) -->
          <div
            class="absolute inset-x-0 bottom-0 px-3 pb-2.5 pt-2 flex items-end justify-between gap-2 text-white pointer-events-none"
          >
            <div class="flex items-center gap-2 min-w-0 flex-1">
              <SenderAvatar :sender="item.sender" :size="22" />
              <div class="flex flex-col min-w-0 leading-tight">
                <span class="text-[12px] font-semibold truncate drop-shadow-sm">
                  {{ item.sender?.name || t('GALLERY.UNKNOWN_SENDER') }}
                </span>
                <span
                  class="text-[10px] text-white/80 drop-shadow-sm tabular-nums"
                >
                  {{ formatTime(item.createdAt) }}
                </span>
              </div>
            </div>
          </div>

          <!-- Selection checkbox (top-left) -->
          <button
            type="button"
            :aria-label="t('GALLERY.ACTIONS.SELECT')"
            class="absolute top-2 ltr:left-2 rtl:right-2 size-7 rounded-full backdrop-blur-md flex items-center justify-center transition-all border-2"
            :class="
              selectedIds.has(item.id)
                ? 'bg-n-brand border-n-brand opacity-100'
                : 'bg-black/40 border-white/70 opacity-0 group-hover:opacity-100'
            "
            @click.stop="$emit('toggleSelect', item.id)"
          >
            <span
              v-if="selectedIds.has(item.id)"
              class="i-lucide-check size-4 text-white"
            />
          </button>

          <!-- Open conversation (top-right) -->
          <button
            type="button"
            :aria-label="t('GALLERY.ACTIONS.OPEN_CONVERSATION')"
            class="absolute top-2 ltr:right-2 rtl:left-2 size-8 rounded-full bg-black/50 hover:bg-black/70 backdrop-blur-md text-white opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center"
            :title="t('GALLERY.ACTIONS.OPEN_CONVERSATION')"
            @click.stop="$emit('openConversation', item)"
          >
            <span class="i-lucide-message-circle size-4" />
          </button>

          <!-- Video duration / file size badge (bottom-right) -->
          <div
            v-if="item.fileType === 'video'"
            class="absolute top-2.5 right-12 px-2 py-0.5 rounded-full bg-black/60 text-white text-[10px] font-medium pointer-events-none"
          >
            <span
              class="i-lucide-video size-3 inline-block align-middle ltr:mr-0.5 rtl:ml-0.5"
            />
          </div>
        </article>
      </div>
    </section>

    <div ref="sentinel" class="h-px w-full" />
    <div v-if="isLoadingMore" class="flex justify-center py-6">
      <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
    </div>
  </div>
</template>
