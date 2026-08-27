<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import BaseBubble from './Base.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../provider.js';

// Carrossel de mídia do WhatsApp Cloud desenhado no painel. A mensagem chega com
// `attachments` VAZIO de propósito: o carrossel é passthrough da Meta, quem baixa a foto é
// ela, pela URL pública do CDN. Sem este componente a bolha caía no TextBubble e o atendente
// via só o `content` ("📷 Carrossel: 9 fotos do imóvel X") — sem saber quais fotos saíram nem
// que botões o cliente tinha à frente.
//
// O payload é contrato da Meta e chega CRU (snake_case): `MessageList#CAMEL_CASE_OPTIONS`
// lista `content_attributes.interactive_payload` em `stopPaths`. Cuidado: stopPaths protege o
// CONTEÚDO, não a chave do topo — por isso `interactivePayload` (camelizada) com
// `card_index` / `quick_reply` (crus) dentro.
const { t } = useI18n();
const { contentAttributes, id, createdAt } = useMessageContext();

const payload = computed(
  () => contentAttributes.value?.interactivePayload ?? {}
);

// Texto que a Meta desenha acima dos cards. Cai no `content` da mensagem quando ausente.
const bodyText = computed(() => payload.value?.body?.text ?? '');

// `card_index` é a ordem do ENVIO: ordenar por ele é reproduzir o que o cliente recebeu, não
// reordenar. Card sem índice mantém a posição do array (fallback estável).
const cards = computed(() => {
  const list = payload.value?.action?.cards;
  if (!Array.isArray(list)) return [];
  return list
    .map((card, index) => ({ card, index }))
    .sort(
      (a, b) =>
        (a.card?.card_index ?? a.index) - (b.card?.card_index ?? b.index)
    )
    .map(({ card }) => card);
});

const imageOf = card => card?.header?.image?.link ?? '';
const captionOf = card => card?.body?.text ?? '';

// Dois formatos de botão, e a Meta não deixa misturar no mesmo carrossel:
//   • quick replies  → action.buttons[].quick_reply.title  (padrão: interesse / visita)
//   • CTA de link    → action.name === 'cta_url' + parameters.display_text
const buttonsOf = card => {
  const action = card?.action ?? {};
  if (Array.isArray(action.buttons)) {
    return action.buttons
      .map(button => button?.quick_reply?.title)
      .filter(Boolean);
  }
  if (action.name === 'cta_url') {
    return [action.parameters?.display_text].filter(Boolean);
  }
  return [];
};

const failedImages = ref(new Set());
const onImageError = index => {
  failedImages.value = new Set(failedImages.value).add(index);
};

// Só as fotos que carregaram entram na galeria: abrir num quadro quebrado não ajuda ninguém.
const galleryAttachments = computed(() =>
  cards.value
    .map((card, index) => ({ card, index }))
    .filter(({ index }) => !failedImages.value.has(index))
    .map(({ card, index }) => ({
      id: `carousel-${id.value}-${index}`,
      message_id: id.value,
      file_type: 'image',
      data_url: imageOf(card),
      thumb_url: imageOf(card),
      filename: captionOf(card),
      created_at: createdAt.value,
    }))
);

const showGallery = ref(false);
const activeAttachment = ref(null);

const openGallery = index => {
  const target = galleryAttachments.value.find(
    item => item.id === `carousel-${id.value}-${index}`
  );
  if (!target) return;
  activeAttachment.value = target;
  showGallery.value = true;
};
</script>

<template>
  <BaseBubble class="overflow-hidden">
    <p
      v-if="bodyText"
      class="px-1 pt-0.5 pb-1.5 whitespace-pre-wrap break-words"
    >
      {{ bodyText }}
    </p>
    <ul
      class="flex gap-1.5 pb-1 overflow-x-auto snap-x snap-mandatory"
      :aria-label="t('COMPONENTS.CAROUSEL_BUBBLE.STRIP_LABEL')"
    >
      <li
        v-for="(card, index) in cards"
        :key="`${id}-card-${index}`"
        class="flex flex-col flex-none w-40 overflow-hidden rounded-lg snap-start bg-[var(--wa-card-bg)] dark:bg-[var(--wa-card-bg-dark)]"
      >
        <button
          v-if="!failedImages.has(index)"
          type="button"
          class="relative block w-full cursor-zoom-in"
          :aria-label="
            t('COMPONENTS.CAROUSEL_BUBBLE.OPEN_PHOTO', {
              index: index + 1,
              total: cards.length,
            })
          "
          @click="openGallery(index)"
        >
          <img
            :src="imageOf(card)"
            :alt="captionOf(card)"
            loading="lazy"
            decoding="async"
            class="object-cover w-full h-28"
            @error="onImageError(index)"
          />
          <span
            class="absolute px-1.5 py-0.5 text-xs rounded right-1 bottom-1 text-n-slate-1 bg-n-alpha-black2"
          >
            {{
              t('COMPONENTS.CAROUSEL_BUBBLE.PHOTO_COUNTER', {
                index: index + 1,
                total: cards.length,
              })
            }}
          </span>
        </button>
        <div
          v-else
          class="grid w-full px-2 text-xs text-center h-28 place-items-center text-[var(--wa-text-secondary)] dark:text-[var(--wa-text-secondary-dark)] bg-[var(--wa-card-divider)] dark:bg-[var(--wa-card-divider-dark)]"
        >
          {{ t('COMPONENTS.CAROUSEL_BUBBLE.PHOTO_UNAVAILABLE') }}
        </div>
        <p
          v-if="captionOf(card)"
          class="px-2 py-1.5 text-xs leading-snug break-words text-[var(--wa-text-primary)] dark:text-[var(--wa-text-primary-dark)]"
        >
          {{ captionOf(card) }}
        </p>
        <div v-if="buttonsOf(card).length" class="mt-auto">
          <!-- Retrato do que o cliente recebeu, não um controle: sem clique, sem foco. O
               atendente precisa VER o botão para entender de onde veio a resposta dele. -->
          <span
            v-for="(label, buttonIndex) in buttonsOf(card)"
            :key="`${id}-card-${index}-btn-${buttonIndex}`"
            class="flex items-center justify-center h-8 px-2 text-xs text-center border-t text-[var(--wa-card-action)] dark:text-[var(--wa-card-action-dark)] border-[var(--wa-card-divider)] dark:border-[var(--wa-card-divider-dark)]"
            :title="t('COMPONENTS.CAROUSEL_BUBBLE.BUTTON_HINT')"
          >
            {{ label }}
          </span>
        </div>
      </li>
    </ul>
    <GalleryView
      v-if="showGallery && activeAttachment"
      v-model:show="showGallery"
      :attachment="activeAttachment"
      :all-attachments="galleryAttachments"
      @close="showGallery = false"
    />
  </BaseBubble>
</template>
