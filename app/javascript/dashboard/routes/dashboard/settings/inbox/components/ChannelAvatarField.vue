<script setup>
/**
 * Foto do atendimento — o controle que antes era um circulo mudo.
 *
 * O que ele resolve, medido na tela de hoje: havia so um `input[type=file]`
 * escondido atras de um circulo com icone generico. Sem galeria, sem formato
 * aceito, sem tamanho, e sem dizer ONDE aquela foto aparece. Quem nao subisse
 * imagem ficava com a inicial do nome no cabecalho do chat do site.
 *
 * Agora: galeria de avatares padrao (um clique aplica), upload da propria
 * imagem, os formatos e o tamanho escritos na tela, e a frase que diz onde a
 * foto vai aparecer.
 *
 * Os avatares padrao sao ilustracoes proprias, em `public/dashboard/images/
 * inbox-avatars/`. Os `.svg` sao a fonte; os `.png` sao o que a galeria serve,
 * porque o backend (`Avatarable#acceptable_avatar`) so aceita jpeg, png e gif —
 * SVG e recusado na validacao.
 *
 * A escolha da galeria emite o MESMO payload do upload (`{ file, url }`), para
 * que quem consome nao precise saber de onde veio o byte.
 */
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  src: { type: String, default: '' },
  name: { type: String, default: '' },
  iconName: { type: String, default: null },
  /** Mostra a frase "aparece no cabecalho e no balao" — so faz sentido no widget. */
  showPlacementHint: { type: Boolean, default: false },
});

const emit = defineEmits(['upload', 'delete']);

const { t } = useI18n();

const GALLERY_BASE = '/dashboard/images/inbox-avatars';
const GALLERY = [
  'atendente-1',
  'atendente-2',
  'atendente-3',
  'atendente-4',
  'atendente-5',
  'atendente-6',
  'atendente-7',
  'atendente-8',
];

const ACCEPTED_MIME = 'image/jpeg,image/png,image/gif';

const fileInput = ref(null);
const pickError = ref('');

const galleryItems = computed(() =>
  GALLERY.map(id => ({ id, url: `${GALLERY_BASE}/${id}.png` }))
);

const selectedGalleryId = computed(() => {
  const match = GALLERY.find(id => props.src?.includes(`${id}.png`));
  return match ?? null;
});

const openFilePicker = () => fileInput.value?.click();

const onFileChange = event => {
  const [file] = event.target.files ?? [];
  if (!file) return;
  pickError.value = '';
  emit('upload', { file, url: URL.createObjectURL(file) });
};

/**
 * Escolher da galeria vira upload de verdade: o PNG e baixado do proprio
 * dominio e virado num `File`, porque o inbox grava a foto no ActiveStorage —
 * guardar so a URL deixaria a foto fora do payload de salvamento.
 */
const pickFromGallery = async item => {
  pickError.value = '';
  try {
    const response = await fetch(item.url);
    if (!response.ok) throw new Error(String(response.status));
    const blob = await response.blob();
    const file = new File([blob], `${item.id}.png`, {
      type: blob.type || 'image/png',
    });
    emit('upload', { file, url: item.url });
  } catch {
    pickError.value = t(
      'INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.GALLERY_ERROR'
    );
  }
};

const removeAvatar = () => {
  if (fileInput.value) fileInput.value.value = null;
  emit('delete');
};
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="channel-avatar-field">
    <div class="flex flex-col gap-1 items-start">
      <label class="text-heading-3 text-n-slate-12">
        {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.LABEL') }}
      </label>
      <p v-if="showPlacementHint" class="text-sm text-n-slate-11 mb-0">
        {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.WHERE_IT_SHOWS') }}
      </p>
    </div>

    <div class="flex items-center gap-4">
      <Avatar
        :src="src"
        :size="64"
        :icon-name="iconName"
        :name="name"
        rounded-full
        data-testid="channel-avatar-current"
      />
      <div class="flex flex-col gap-1.5 items-start min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-sm font-medium cursor-pointer bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
            data-testid="channel-avatar-upload"
            @click="openFilePicker"
          >
            <Icon icon="i-lucide-upload" class="size-4 shrink-0" />
            {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.UPLOAD') }}
          </button>
          <button
            v-if="src"
            type="button"
            class="inline-flex items-center h-8 px-3 rounded-lg text-sm font-medium cursor-pointer bg-transparent text-n-slate-11 hover:text-n-slate-12"
            data-testid="channel-avatar-remove"
            @click="removeAvatar"
          >
            {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.REMOVE') }}
          </button>
        </div>
        <p
          class="text-sm text-n-slate-11 mb-0"
          data-testid="channel-avatar-specs"
        >
          {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.SPECS') }}
        </p>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.GALLERY_LABEL') }}
      </span>
      <ul
        class="flex flex-wrap gap-2 list-none m-0 p-0"
        data-testid="channel-avatar-gallery"
      >
        <li v-for="item in galleryItems" :key="item.id">
          <button
            type="button"
            class="flex p-0 rounded-full cursor-pointer bg-transparent outline outline-2 -outline-offset-1 transition-all duration-150 focus-visible:outline-n-brand"
            :class="
              selectedGalleryId === item.id
                ? 'outline-n-brand'
                : 'outline-transparent hover:outline-n-strong'
            "
            :aria-pressed="selectedGalleryId === item.id"
            :title="
              t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.GALLERY_ITEM', {
                number: item.id.split('-').pop(),
              })
            "
            :data-testid="`channel-avatar-option-${item.id}`"
            @click="pickFromGallery(item)"
          >
            <img
              :src="item.url"
              :alt="
                t(
                  'INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_AVATAR.GALLERY_ITEM',
                  { number: item.id.split('-').pop() }
                )
              "
              width="40"
              height="40"
              class="size-10 rounded-full block"
            />
          </button>
        </li>
      </ul>
      <p
        v-if="pickError"
        class="text-sm text-n-ruby-11 mb-0"
        data-testid="channel-avatar-error"
      >
        {{ pickError }}
      </p>
    </div>

    <input
      ref="fileInput"
      type="file"
      :accept="ACCEPTED_MIME"
      class="hidden"
      data-testid="channel-avatar-input"
      @change="onFileChange"
    />
  </div>
</template>
