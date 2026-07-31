<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useBulkDownload } from 'dashboard/composables/useBulkDownload';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  // A aba inicial é controlada pelo Strip para sobreviver ao ida-e-volta do
  // lightbox (o painel desmonta enquanto a galeria está aberta).
  initialTab: {
    type: String,
    default: 'media',
  },
});

// A galeria é teleportada para o body e ficaria ATRÁS do <dialog> modal (top
// layer). Por isso o painel não abre o lightbox: ele pede ao Strip, que fecha o
// dialog antes de mostrar a galeria.
const emit = defineEmits(['openGallery', 'tabChange']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const PAGE_SIZE = 18;

// Backend enum: image=>0, audio=>1, video=>2, file=>3, embed=>12, ig_reel=>9
const FILE_TYPE_ENUM = {
  0: 'image',
  1: 'audio',
  2: 'video',
  3: 'file',
  9: 'ig_reel',
  12: 'embed',
};

const normalizeFileType = attachment => {
  if (!attachment) return null;
  const ft = attachment.file_type;
  if (typeof ft === 'string') return ft;
  return FILE_TYPE_ENUM[ft] ?? 'file';
};

const attachmentsRaw = computed(() => {
  const list = getters.getSelectedChatAttachments?.value ?? [];
  return Array.isArray(list) ? list : [];
});

const attachmentsMeta = computed(
  () => getters.getSelectedChatAttachmentsMeta?.value ?? {}
);

const fetchAttachments = () => {
  if (props.conversationId) {
    store.dispatch('fetchAllAttachments', props.conversationId).catch(() => {});
  }
};

onMounted(fetchAttachments);

// A API devolve os anexos em ordem decrescente de created_at, mas o store
// ANEXA no fim os que chegam ao vivo (ADD_CONVERSATION_ATTACHMENTS) — e esses
// vêm do payload da mensagem, sem created_at. Sem reordenar, a foto recém
// enviada aparecia por último na grade (ou escondida atrás do "Ver mais").
const recencyRank = att => att?.created_at ?? Number.MAX_SAFE_INTEGER;
const attachmentRowId = att => Number(att?.id) || 0;

const sortedAttachments = computed(() =>
  [...attachmentsRaw.value].sort(
    (a, b) =>
      recencyRank(b) - recencyRank(a) || attachmentRowId(b) - attachmentRowId(a)
  )
);

// Filtrar preserva "mais recente primeiro" em cada aba.
const grouped = computed(() => {
  const groups = { media: [], docs: [], embed: [] };
  sortedAttachments.value.forEach(att => {
    const type = normalizeFileType(att);
    if (!type) return;
    if (type === 'image' || type === 'video' || type === 'ig_reel') {
      groups.media.push(att);
    } else if (type === 'audio' || type === 'file') {
      groups.docs.push(att);
    } else if (type === 'embed') {
      groups.embed.push(att);
    }
  });
  return groups;
});

const isVideo = att => {
  const type = normalizeFileType(att);
  return type === 'video' || type === 'ig_reel';
};

const isAudio = att => normalizeFileType(att) === 'audio';

// --- Links -------------------------------------------------------------------
// O endpoint de anexos só devolve image/video/audio/file — nunca embed. A fonte
// pronta de links são as mensagens já carregadas em memória: varrer o conteúdo
// delas é barato (nada de request extra).
const URL_PATTERN = /https?:\/\/[^\s<>"'`]+/gi;
const ACTIVITY_MESSAGE_TYPE = 2;

const chatMessages = computed(() => {
  const messages = getters.getSelectedChat?.value?.messages;
  return Array.isArray(messages) ? messages : [];
});

const links = computed(() => {
  const seen = new Set();
  const collected = [];

  const push = (rawUrl, message) => {
    // Pontuação final costuma grudar na URL quando ela fecha a frase.
    const url = String(rawUrl).replace(/[.,;:!?)\]}>'"]+$/, '');
    if (!url || seen.has(url)) return;
    seen.add(url);
    collected.push({ url, messageId: message?.id ?? url });
  };

  grouped.value.embed.forEach(att => {
    const url = att?.data_url || att?.external_url;
    if (url) push(url, { id: att.id ?? att.message_id });
  });

  // Mensagens vêm em ordem crescente; invertemos para listar as mais recentes.
  [...chatMessages.value].reverse().forEach(message => {
    if (!message?.content) return;
    if (message.message_type === ACTIVITY_MESSAGE_TYPE) return;
    const matches = String(message.content).match(URL_PATTERN) ?? [];
    matches.forEach(match => push(match, message));
  });

  return collected;
});

const getLinkHost = url => {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
};

// --- Abas --------------------------------------------------------------------
const TAB_KEYS = ['media', 'docs', 'links'];

const activeTab = ref(
  TAB_KEYS.includes(props.initialTab) ? props.initialTab : 'media'
);

const listFor = key => {
  if (key === 'media') return grouped.value.media;
  if (key === 'docs') return grouped.value.docs;
  return links.value;
};

const tabs = computed(() => [
  {
    key: 'media',
    label: t('CONVERSATION_SIDEBAR.MEDIA_STRIP.TABS.MEDIA'),
    count: grouped.value.media.length,
  },
  {
    key: 'docs',
    label: t('CONVERSATION_SIDEBAR.MEDIA_STRIP.TABS.DOCS'),
    count: grouped.value.docs.length,
  },
  {
    key: 'links',
    label: t('CONVERSATION_SIDEBAR.MEDIA_STRIP.TABS.LINKS'),
    count: links.value.length,
  },
]);

const setActiveTab = key => {
  activeTab.value = key;
  emit('tabChange', key);
};

// --- Paginação ---------------------------------------------------------------
const buildCounts = () => ({
  media: PAGE_SIZE,
  docs: PAGE_SIZE,
  links: PAGE_SIZE,
});

const visibleCounts = ref(buildCounts());
const isLoadingMore = ref(false);

const visibleMedia = computed(() =>
  grouped.value.media.slice(0, visibleCounts.value.media)
);
const visibleDocs = computed(() =>
  grouped.value.docs.slice(0, visibleCounts.value.docs)
);
const visibleLinks = computed(() =>
  links.value.slice(0, visibleCounts.value.links)
);

// O store só carrega a página 1 dos anexos; as demais entram sob demanda.
const hasMorePages = computed(() => {
  const { currentPage = 1, totalPages = 1 } = attachmentsMeta.value ?? {};
  return currentPage < totalPages;
});

const hasMoreIn = key => {
  const loadedMore = listFor(key).length > visibleCounts.value[key];
  if (key === 'links') return loadedMore;
  return loadedMore || hasMorePages.value;
};

const remainingIn = key => {
  const remaining = listFor(key).length - visibleCounts.value[key];
  return remaining > 0 ? Math.min(remaining, PAGE_SIZE) : PAGE_SIZE;
};

const showMore = async key => {
  visibleCounts.value[key] += PAGE_SIZE;
  const exhaustedLoaded = visibleCounts.value[key] >= listFor(key).length;
  if (key === 'links' || !exhaustedLoaded || !hasMorePages.value) return;
  if (isLoadingMore.value) return;

  isLoadingMore.value = true;
  try {
    await store.dispatch('fetchMoreAttachments', props.conversationId);
  } catch {
    // silencioso: a lista simplesmente não cresce
  } finally {
    isLoadingMore.value = false;
  }
};

// --- Miniaturas / nomes ------------------------------------------------------
const prewarmedVideoPreviewKeys = ref(new Set());

const resolveAttachmentKey = (attachment, index) =>
  attachment?.id ?? attachment?.message_id ?? index;

const prewarmVideoPreview = (attachment, index) => {
  if (!attachment?.data_url) return;

  const key = resolveAttachmentKey(attachment, index);
  if (prewarmedVideoPreviewKeys.value.has(key)) return;

  prewarmedVideoPreviewKeys.value = new Set([
    ...prewarmedVideoPreviewKeys.value,
    key,
  ]);
};

const getVideoPreviewSrc = (attachment, index) => {
  const key = resolveAttachmentKey(attachment, index);
  return prewarmedVideoPreviewKeys.value.has(key) ? attachment.data_url : '';
};

const getThumbSrc = att => att?.thumb_url || att?.data_url || '';

const getFileName = att => {
  if (att?.filename) return att.filename;
  const url = att?.data_url;
  if (!url) return t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT');
  try {
    const path = url.split('?')[0];
    const segment = path.split('/').pop();
    return (
      decodeURIComponent(segment || '') ||
      t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT')
    );
  } catch {
    return t('CONVERSATION_SIDEBAR.MEDIA_SECTIONS.DOCUMENT');
  }
};

// --- Download em massa (zip assíncrono) + modo seleção -----------------------
const { status, processed, total, errorMeta, isPreparing, isStarting, start } =
  useBulkDownload();

const selectionMode = ref(false);
const selectedIds = ref(new Set());

// "Baixar todas" cobre os tipos com arquivo (imagens, vídeos, áudios, docs) —
// links não entram no zip.
const downloadableCount = computed(
  () => grouped.value.media.length + grouped.value.docs.length
);

const selectedCount = computed(() => selectedIds.value.size);
const isItemSelected = att => att?.id != null && selectedIds.value.has(att.id);

const toggleItem = att => {
  if (att?.id == null) return;
  const next = new Set(selectedIds.value);
  if (next.has(att.id)) next.delete(att.id);
  else next.add(att.id);
  selectedIds.value = next;
};

const enterSelection = () => {
  selectionMode.value = true;
};

function exitSelection() {
  selectionMode.value = false;
  selectedIds.value = new Set();
}

// Em modo seleção o clique alterna o item; fora dele, abre o lightbox.
const onMediaClick = att => {
  if (selectionMode.value) {
    toggleItem(att);
    return;
  }
  emit('openGallery', { attachment: att, list: grouped.value.media });
};

// Documentos são <a> — em modo seleção interceptamos o clique para alternar.
const onFileClick = (event, att) => {
  if (selectionMode.value) {
    event.preventDefault();
    toggleItem(att);
  }
};

const downloadAll = () => start({ conversationId: props.conversationId });

const downloadSelected = () => {
  if (!selectedIds.value.size) return;
  start({
    attachmentIds: [...selectedIds.value],
    conversationId: props.conversationId,
  });
};

watch(status, value => {
  if (value === 'ready') {
    useAlert(t('GALLERY.BULK.READY'));
  } else if (value === 'error' && errorMeta.value) {
    useAlert(t(errorMeta.value.key, errorMeta.value.params));
  }
});

// Troca de conversa: reseta paginação/seleção e recarrega.
watch(
  () => props.conversationId,
  () => {
    visibleCounts.value = buildCounts();
    exitSelection();
    fetchAttachments();
  }
);
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0 gap-3 text-sm">
    <!-- Abas -->
    <div
      role="tablist"
      class="flex items-center gap-1 p-1 rounded-lg shrink-0 bg-n-alpha-2"
    >
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        role="tab"
        :aria-selected="activeTab === tab.key"
        class="flex items-center justify-center flex-1 h-8 gap-1 text-sm font-medium transition-colors rounded-md"
        :class="
          activeTab === tab.key
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="setActiveTab(tab.key)"
      >
        {{ tab.label }}
        <span v-if="tab.count" class="text-xs text-n-slate-10">
          {{ tab.count }}
        </span>
      </button>
    </div>

    <!-- Barra de ações de download em massa — CTA primário de largura total.
         Só aparece quando há ao menos 1 arquivo baixável: conversa só com links
         não mostra "Baixar todas (0)". -->
    <div
      v-if="downloadableCount > 0 && activeTab !== 'links'"
      class="flex flex-col gap-2 shrink-0"
    >
      <!-- Preparando o zip -->
      <div
        v-if="isPreparing"
        class="flex items-center justify-center w-full gap-2 text-sm font-medium rounded-lg h-9 bg-n-brand/10 text-n-brand"
      >
        <Icon icon="i-lucide-loader-2" class="size-4 animate-spin" />
        {{
          total > 0
            ? t('CONVERSATION_SIDEBAR.BULK.PREPARING', { processed, total })
            : t('CONVERSATION_SIDEBAR.BULK.PREPARING_INDEFINITE')
        }}
      </div>

      <!-- Ações padrão -->
      <template v-else-if="!selectionMode">
        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="isStarting"
            class="flex items-center justify-center flex-1 gap-2 text-sm font-semibold text-white transition-colors rounded-lg shadow-sm h-9 bg-n-brand hover:bg-n-brand/90 disabled:opacity-50 disabled:cursor-not-allowed"
            @click="downloadAll"
          >
            <Icon icon="i-lucide-download" class="size-4" />
            {{
              t('CONVERSATION_SIDEBAR.BULK.DOWNLOAD_ALL', {
                count: downloadableCount,
              })
            }}
          </button>
          <button
            type="button"
            class="flex items-center justify-center gap-1.5 h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors shrink-0"
            @click="enterSelection"
          >
            <Icon icon="i-lucide-check-square" class="size-3.5" />
            {{ t('CONVERSATION_SIDEBAR.BULK.SELECT') }}
          </button>
        </div>
      </template>

      <!-- Modo seleção -->
      <template v-else>
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-n-slate-12">
            {{
              t('CONVERSATION_SIDEBAR.BULK.SELECTED_COUNT', {
                count: selectedCount,
              })
            }}
          </span>
          <button
            type="button"
            class="text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="exitSelection"
          >
            {{ t('CONVERSATION_SIDEBAR.BULK.CANCEL') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="!selectedCount || isStarting"
          class="flex items-center justify-center w-full gap-2 text-sm font-semibold text-white transition-colors rounded-lg shadow-sm h-9 bg-n-brand hover:bg-n-brand/90 disabled:opacity-40 disabled:cursor-not-allowed"
          @click="downloadSelected"
        >
          <Icon icon="i-lucide-download" class="size-4" />
          {{ t('CONVERSATION_SIDEBAR.BULK.DOWNLOAD_SELECTED') }}
        </button>
      </template>
    </div>

    <!-- Conteúdo rolável: min-h-0 + flex-1 para o rodapé do dialog não vazar -->
    <div class="flex-1 min-h-0 overflow-y-auto">
      <!-- Mídia (imagens + vídeos) -->
      <template v-if="activeTab === 'media'">
        <p
          v-if="!grouped.media.length"
          class="py-6 text-center text-n-slate-11"
        >
          {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.EMPTY_TABS.MEDIA') }}
        </p>
        <div v-else class="grid grid-cols-3 gap-1">
          <button
            v-for="(att, idx) in visibleMedia"
            :key="att.id ?? att.message_id ?? idx"
            type="button"
            class="relative overflow-hidden transition-opacity rounded-lg cursor-pointer aspect-square bg-n-slate-2 hover:opacity-80 focus:outline-none focus:ring-2 focus:ring-n-blue"
            :class="{ 'ring-2 ring-n-brand': isItemSelected(att) }"
            @pointerenter="prewarmVideoPreview(att, idx)"
            @pointerdown="prewarmVideoPreview(att, idx)"
            @touchstart.passive="prewarmVideoPreview(att, idx)"
            @focus="prewarmVideoPreview(att, idx)"
            @click="onMediaClick(att)"
          >
            <span
              v-if="selectionMode"
              class="absolute z-10 flex items-center justify-center border-2 rounded-md top-1 ltr:left-1 rtl:right-1 size-5"
              :class="
                isItemSelected(att)
                  ? 'bg-n-brand border-n-brand text-white'
                  : 'bg-black/30 border-white/70'
              "
            >
              <Icon
                v-if="isItemSelected(att)"
                icon="i-lucide-check"
                class="size-3.5"
              />
            </span>
            <img
              v-if="getThumbSrc(att) && !isVideo(att)"
              :src="getThumbSrc(att)"
              class="object-cover w-full h-full"
              alt=""
            />
            <template v-else-if="isVideo(att)">
              <img
                v-if="att.thumb_url"
                :src="att.thumb_url"
                class="object-cover w-full h-full"
                alt=""
              />
              <video
                v-else-if="att.data_url"
                :src="getVideoPreviewSrc(att, idx)"
                class="object-cover w-full h-full"
                muted
                playsinline
                preload="none"
              />
              <div
                class="absolute inset-0 flex items-center justify-center bg-black/20"
              >
                <Icon
                  icon="i-teenyicons-play-small-solid"
                  class="text-white size-7"
                />
              </div>
            </template>
            <div
              v-else
              class="flex items-center justify-center w-full h-full text-n-slate-10"
            >
              <Icon icon="i-lucide-image" class="size-6" />
            </div>
          </button>
        </div>
        <button
          v-if="grouped.media.length && hasMoreIn('media')"
          type="button"
          class="w-full py-1 mt-2 text-xs text-center text-n-blue-text hover:underline"
          :disabled="isLoadingMore"
          @click="showMore('media')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: remainingIn('media') })
          }}
        </button>
      </template>

      <!-- Documentos e áudios -->
      <template v-else-if="activeTab === 'docs'">
        <p v-if="!grouped.docs.length" class="py-6 text-center text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.EMPTY_TABS.DOCS') }}
        </p>
        <ul v-else class="flex flex-col gap-1.5">
          <li
            v-for="(att, idx) in visibleDocs"
            :key="att.id ?? att.message_id ?? idx"
          >
            <!-- Áudio: player inline, sem sair do painel -->
            <div
              v-if="isAudio(att)"
              class="flex items-center gap-2 px-3 py-2 border rounded-md bg-n-slate-2"
              :class="
                isItemSelected(att)
                  ? 'border-n-brand ring-1 ring-n-brand'
                  : 'border-n-weak'
              "
            >
              <button
                v-if="selectionMode"
                type="button"
                class="shrink-0"
                @click="toggleItem(att)"
              >
                <Icon
                  :icon="
                    isItemSelected(att)
                      ? 'i-lucide-check-square'
                      : 'i-lucide-square'
                  "
                  class="size-4"
                  :class="
                    isItemSelected(att) ? 'text-n-brand' : 'text-n-slate-10'
                  "
                />
              </button>
              <Icon
                v-else
                icon="i-lucide-volume-2"
                class="size-4 text-n-slate-11 shrink-0"
              />
              <audio
                :src="att.data_url"
                controls
                preload="none"
                class="w-full h-8 min-w-0"
              />
            </div>

            <!-- Documento -->
            <a
              v-else
              :href="att.data_url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 px-3 py-2 truncate border rounded-md bg-n-slate-2 text-n-slate-12 hover:bg-n-slate-3"
              :class="
                isItemSelected(att)
                  ? 'border-n-brand ring-1 ring-n-brand'
                  : 'border-n-weak'
              "
              @click="onFileClick($event, att)"
            >
              <Icon
                v-if="selectionMode"
                :icon="
                  isItemSelected(att)
                    ? 'i-lucide-check-square'
                    : 'i-lucide-square'
                "
                class="size-4 shrink-0"
                :class="
                  isItemSelected(att) ? 'text-n-brand' : 'text-n-slate-10'
                "
              />
              <Icon
                v-else
                icon="i-lucide-file-down"
                class="size-4 text-n-slate-11 shrink-0"
              />
              <span class="flex-1 truncate">{{ getFileName(att) }}</span>
            </a>
          </li>
        </ul>
        <button
          v-if="grouped.docs.length && hasMoreIn('docs')"
          type="button"
          class="w-full py-1 mt-2 text-xs text-center text-n-blue-text hover:underline"
          :disabled="isLoadingMore"
          @click="showMore('docs')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: remainingIn('docs') })
          }}
        </button>
      </template>

      <!-- Links -->
      <template v-else>
        <p v-if="!links.length" class="py-6 text-center text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.MEDIA_STRIP.EMPTY_TABS.LINKS') }}
        </p>
        <ul v-else class="flex flex-col gap-1.5">
          <li
            v-for="(link, idx) in visibleLinks"
            :key="`${link.messageId}-${idx}`"
          >
            <a
              :href="link.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 px-3 py-2 border rounded-md border-n-weak bg-n-slate-2 hover:bg-n-slate-3"
            >
              <Icon
                icon="i-lucide-external-link"
                class="size-4 shrink-0 text-n-slate-11"
              />
              <span class="flex flex-col min-w-0">
                <span class="text-sm truncate text-n-slate-12">
                  {{ getLinkHost(link.url) }}
                </span>
                <span class="text-xs truncate text-n-slate-11">
                  {{ link.url }}
                </span>
              </span>
            </a>
          </li>
        </ul>
        <button
          v-if="links.length && hasMoreIn('links')"
          type="button"
          class="w-full py-1 mt-2 text-xs text-center text-n-blue-text hover:underline"
          @click="showMore('links')"
        >
          {{
            t('CONVERSATION_SIDEBAR.SHOW_MORE', { count: remainingIn('links') })
          }}
        </button>
      </template>
    </div>
  </div>
</template>
