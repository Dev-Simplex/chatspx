<script setup>
import { computed, ref, watch } from 'vue';
import { removeEmoji } from 'shared/helpers/emoji';

/**
 * Avatar do WIDGET — bloco 1.08.
 *
 * Existe para o widget parar de importar `dashboard/components-next/avatar/Avatar.vue`.
 * Aquele componente tem 364 linhas e arrasta, por import estático, `Icon.vue`,
 * `GalleryView.vue`, `button/Button.vue` e `spinner/Spinner.vue` — 27.619 B de
 * utilitárias no CSS do widget, para uma tela que usa CINCO props: `src`,
 * `size`, `name`, `status` e `rounded-full`. Upload, preview em galeria, slots
 * de badge e overlay, tooltip e ícones lucide nunca são exercitados aqui.
 *
 * ⚠️ ESTE COMPONENTE É UMA RÉPLICA PIXEL A PIXEL, NÃO UM REDESENHO.
 *
 * A tela de mensagens não lidas é uma das quatro que os 16 snapshots do widget
 * cobrem, e a régua não se move para acomodar refatoração. Por isso os valores
 * abaixo — as doze cores de iniciais, o `outline` de 1px com alfa 0.03/0.04, o
 * badge a 35% do tamanho com mínimo de 8px e o topo/esquerda em `size - badge/1.1`
 * — são os do original, copiados, não recalculados. Mudar qualquer um deles é
 * mudar pixel de uma tela coberta por snapshot.
 *
 * A ÚNICA divergência deliberada é a cor do badge `online`: o original usa
 * `bg-n-brand`, o literal `#2dc46f` que o bloco 1.04 baniu de `widget/`,
 * `sdk/` e `shared/`. Aqui é `bg-w-brand`, que resolve pelo token da inbox.
 * Não muda o pixel do snapshot porque o harness usa `widgetColor: '#2DC46F'` e
 * não emite tokens, então o fallback de `_tokens.scss` dá exatamente a mesma cor.
 * Com uma inbox de outra cor, o ponto de presença passa a acompanhá-la — que é
 * o que a onda inteira está corrigindo.
 */
const props = defineProps({
  src: { type: String, default: '' },
  name: { type: String, required: true },
  size: { type: Number, default: 32 },
  roundedFull: { type: Boolean, default: false },
  status: { type: String, default: null },
});

// As doze cores do original. `light[i]` e `dark[i]` são pares [fundo, texto].
const AVATAR_COLORS = {
  dark: [
    ['#4B143D', '#FF8DCC'],
    ['#3F220D', '#FFA366'],
    ['#2A2A2A', '#ADB1B8'],
    ['#023B37', '#0BD8B6'],
    ['#27264D', '#A19EFF'],
    ['#1D2E62', '#9EB1FF'],
  ],
  light: [
    ['#FBDCEF', '#C2298A'],
    ['#FFE0BB', '#99543A'],
    ['#E8E8E8', '#60646C'],
    ['#CCF3EA', '#008573'],
    ['#EBEBFE', '#4747C2'],
    ['#E1E9FF', '#3A5BC7'],
  ],
  default: { bg: '#E8E8E8', text: '#60646C' },
};

const STATUS_CLASSES = {
  online: 'bg-w-brand',
  busy: 'bg-n-amber-10',
  offline: 'bg-n-slate-8',
};

const isImageValid = ref(true);

const showDefaultAvatar = computed(() => !props.src && !props.name);

const initials = computed(() => {
  if (!props.name) return '';
  const words = removeEmoji(props.name).split(/\s+/);
  return words.length === 1
    ? words[0].charAt(0).toUpperCase()
    : words
        .slice(0, 2)
        .map(word => word.charAt(0))
        .join('')
        .toUpperCase();
});

const colors = computed(() => {
  if (!props.name) return AVATAR_COLORS.default;
  const index = props.name.length % AVATAR_COLORS.light.length;
  return {
    bg: AVATAR_COLORS.light[index][0],
    darkBg: AVATAR_COLORS.dark[index][0],
    text: AVATAR_COLORS.light[index][1],
    darkText: AVATAR_COLORS.dark[index][1],
  };
});

const containerStyles = computed(() => ({
  width: `${props.size}px`,
  height: `${props.size}px`,
}));

const usaIniciais = computed(
  () => !showDefaultAvatar.value && (!props.src || !isImageValid.value)
);

const borderRadiusClass = computed(() => {
  if (props.roundedFull) return 'rounded-full';
  if (props.size <= 16) return 'rounded';
  if (props.size <= 24) return 'rounded-md';
  if (props.size <= 32) return 'rounded-lg';
  if (props.size <= 48) return 'rounded-xl';
  return 'rounded-2xl';
});

const avatarStyles = computed(() => ({
  ...containerStyles.value,
  backgroundColor: usaIniciais.value ? colors.value.bg : undefined,
  color: usaIniciais.value ? colors.value.text : undefined,
  '--dark-bg': colors.value.darkBg,
  '--dark-text': colors.value.darkText,
}));

const badgeStyles = computed(() => {
  const badgeSize = Math.max(props.size * 0.35, 8);
  return {
    width: `${badgeSize}px`,
    height: `${badgeSize}px`,
    top: `${props.size - badgeSize / 1.1}px`,
    left: `${props.size - badgeSize / 1.1}px`,
  };
});

const initialsStyles = computed(() => ({
  fontSize: `${Math.min(props.size / 2.5, 24)}px`,
}));

const iconStyles = computed(() => ({
  width: `${props.size / 1.6}px`,
  height: `${props.size / 1.6}px`,
}));

const invalidateCurrentImage = () => {
  isImageValid.value = false;
};

watch(
  () => props.src,
  () => {
    isImageValid.value = true;
  }
);
</script>

<template>
  <span
    class="relative inline-flex z-0 flex-shrink-0 align-middle"
    :style="containerStyles"
  >
    <div
      v-if="status"
      class="absolute z-20 border rounded-full border-n-slate-3"
      :style="badgeStyles"
      :class="STATUS_CLASSES[status]"
    />
    <!-- `aria-label` obrigatório aqui, e a razão é contraintuitiva: `role="img"`
         REMOVE os filhos da árvore de acessibilidade. As iniciais "ML" que
         aparecem na tela não são lidas — para o leitor de tela este nó é uma
         imagem sem nome, que é a violação `role-img-alt` do axe.
         Herdado do `Avatar` do dashboard, que este componente replicou fielmente
         em 1.08: a réplica trouxe o defeito junto. Medido na triagem de 18/08 em
         `messages`, `home` e `unread`. Não muda um pixel. -->
    <span
      role="img"
      :aria-label="name || undefined"
      class="relative inline-flex items-center justify-center object-cover overflow-hidden font-medium outline outline-1 -outline-offset-1 outline-[rgb(0_0_0_/_0.03)] dark:outline-[rgb(255_255_255_/_0.04)]"
      :class="[
        borderRadiusClass,
        {
          'dark:!bg-[var(--dark-bg)] dark:!text-[var(--dark-text)]':
            usaIniciais,
          'bg-n-slate-3 dark:bg-n-slate-4': showDefaultAvatar,
        },
      ]"
      :style="avatarStyles"
    >
      <img
        v-if="src && isImageValid"
        :src="src"
        :alt="name"
        @error="invalidateCurrentImage"
      />
      <span
        v-else-if="!showDefaultAvatar"
        :style="initialsStyles"
        class="select-none"
      >
        {{ initials }}
      </span>
      <!-- Sem nome E sem imagem. O original desenha `i-lucide-user`, que viria do
           `Icon.vue` do dashboard — justamente o import que este componente existe
           para cortar. SVG inline, sem dependência e sem byte de CSS. -->
      <svg
        v-else
        :style="iconStyles"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
        <circle cx="12" cy="7" r="4" />
      </svg>
    </span>
  </span>
</template>
