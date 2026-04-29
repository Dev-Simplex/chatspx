<script setup>
import { onBeforeUnmount, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import SenderAvatar from './SenderAvatar.vue';
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

const emit = defineEmits(['toggleSelect', 'openConversation', 'loadMore']);

const { t } = useI18n();
const groups = useGroupedByDate(toRef(props, 'items'), t);
const sentinel = ref(null);
let observer = null;

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

const hostnameOf = url => {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch (e) {
    return url;
  }
};

const stripUrls = (content, urls) => {
  if (!content) return '';
  let text = content;
  urls.forEach(u => {
    text = text.replace(u, '');
  });
  return text.trim();
};

const faviconUrl = url => {
  try {
    const u = new URL(url);
    return `https://www.google.com/s2/favicons?domain=${u.hostname}&sz=64`;
  } catch (e) {
    return '';
  }
};
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <section v-for="group in groups" :key="group.key" class="mb-8 last:mb-0">
      <h3
        class="sticky -top-px z-20 -mx-6 sm:-mx-8 lg:-mx-10 px-6 sm:px-8 lg:px-10 py-3 mb-3 text-[13px] uppercase tracking-wider font-semibold text-n-slate-11 bg-n-background/95 dark:bg-n-solid-1/95 backdrop-blur"
      >
        {{ group.label }}
      </h3>

      <ul class="flex flex-col gap-2">
        <li
          v-for="item in group.items"
          :key="item.id"
          class="group flex items-start gap-3 py-4 px-4 rounded-2xl transition-all border border-transparent [content-visibility:auto] [contain-intrinsic-size:0_120px]"
          :class="
            selectedIds.has(item.id)
              ? 'bg-n-brand/10 !border-n-brand/40'
              : 'hover:bg-n-alpha-1 dark:hover:bg-n-slate-9/30 hover:border-n-weak/60'
          "
        >
          <!-- Checkbox -->
          <button
            type="button"
            class="size-5 rounded-md flex items-center justify-center flex-shrink-0 transition-colors border-2 mt-1"
            :class="
              selectedIds.has(item.id)
                ? 'bg-n-brand border-n-brand'
                : 'border-n-slate-7 dark:border-n-slate-9 group-hover:border-n-slate-9 dark:group-hover:border-n-slate-7'
            "
            @click="$emit('toggleSelect', item.id)"
          >
            <span
              v-if="selectedIds.has(item.id)"
              class="i-lucide-check size-3.5 text-white"
            />
          </button>

          <!-- Favicon -->
          <div
            class="size-12 rounded-2xl bg-n-solid-2 dark:bg-n-solid-3 flex items-center justify-center flex-shrink-0 overflow-hidden"
          >
            <img
              v-if="item.urls?.[0]"
              :src="faviconUrl(item.urls[0])"
              :alt="hostnameOf(item.urls[0])"
              class="size-7"
              loading="lazy"
              referrerpolicy="no-referrer"
              @error="$event.target.style.display = 'none'"
            />
            <span v-else class="i-lucide-link size-5 text-n-slate-10" />
          </div>

          <!-- Conteúdo -->
          <div class="flex-1 min-w-0">
            <!-- URL principal -->
            <a
              v-if="item.urls?.[0]"
              :href="item.urls[0]"
              target="_blank"
              rel="noopener noreferrer"
              class="text-sm font-semibold text-n-brand hover:underline truncate block"
              @click.stop
            >
              {{ hostnameOf(item.urls[0]) }}
            </a>

            <!-- Descrição (content sem urls) -->
            <p
              v-if="stripUrls(item.content, item.urls)"
              class="text-xs text-n-slate-11 mt-1 line-clamp-2"
            >
              {{ stripUrls(item.content, item.urls) }}
            </p>

            <!-- URL completa -->
            <a
              v-if="item.urls?.[0]"
              :href="item.urls[0]"
              target="_blank"
              rel="noopener noreferrer"
              class="text-[11px] text-n-slate-10 hover:text-n-brand truncate block mt-1"
              @click.stop
            >
              {{ item.urls[0] }}
            </a>

            <!-- Sender + hora -->
            <div class="flex items-center gap-2 mt-2">
              <SenderAvatar :sender="item.sender" :size="18" />
              <span class="text-xs text-n-slate-11 truncate">
                {{ item.sender?.name || t('GALLERY.UNKNOWN_SENDER') }}
              </span>
              <span
                class="text-xs text-n-slate-10 tabular-nums"
                aria-hidden="true"
              >
                &middot;
              </span>
              <span class="text-xs text-n-slate-10 tabular-nums">
                {{ formatTime(item.createdAt) }}
              </span>
              <span
                v-if="item.urls && item.urls.length > 1"
                class="ml-auto text-[10px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ `+${item.urls.length - 1}` }}
              </span>
            </div>
          </div>

          <!-- Open conversation -->
          <button
            type="button"
            class="size-9 rounded-xl hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-11 hover:text-n-slate-12 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0"
            :title="t('GALLERY.ACTIONS.OPEN_CONVERSATION')"
            @click="$emit('openConversation', item)"
          >
            <span class="i-lucide-message-circle size-4" />
          </button>
        </li>
      </ul>
    </section>

    <div ref="sentinel" class="h-px w-full" />
    <div v-if="isLoadingMore" class="flex justify-center py-6">
      <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
    </div>
  </div>
</template>
