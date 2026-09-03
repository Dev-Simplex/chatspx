<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * BLOCO 4.10 — as estrelas do CSAT viram um grupo de rádio de verdade.
 *
 * Três defeitos que este componente tinha, e cada um aparecia na tela de alguém:
 *
 * 1. `aria-label="Star 3"` — INGLÊS CRAVADO, numa conta em pt-BR, num produto em
 *    que pt-BR é prioridade. Agora sai do i18n, e o texto diz a escala inteira
 *    ("3 estrelas de 5"), porque "3" sozinho não informa de quanto.
 * 2. Cinco `<button>` soltos NÃO são um controle de escolha única. O leitor de
 *    tela anunciava cinco botões independentes, sem dizer que escolher um
 *    desmarca os outros nem em que posição da escala cada um está. Agora é
 *    `role="radiogroup"` + `role="radio"` com `aria-checked`.
 * 3. Alvo de ~32 px (`p-1` em volta de um ícone de 24). O aceite do bloco pede
 *    **44×44**, que é o mínimo do SC 2.5.8 — e é o que faz a estrela ser
 *    clicável com o polegar sem acertar a vizinha.
 *
 * O teclado vem junto porque `radiogroup` sem setas é papel mentindo: quem chega
 * por Tab entra no selecionado (ou no primeiro) e caminha com as setas, com um
 * único ponto de parada no grupo — `tabindex` rotativo.
 */
const props = defineProps({
  selectedRating: { type: Number, default: null },
  isDisabled: { type: Boolean, default: false },
});

const emit = defineEmits(['selectRating']);

const { t } = useI18n();

const starRatings = [1, 2, 3, 4, 5];
const hoveredRating = ref(0);

// Chave literal por posição: chave montada em runtime não é conferível pelo
// lint de i18n, e uma que faltasse viraria texto cru na tela do visitante.
const STAR_LABELS = {
  1: 'CSAT.STARS.ONE',
  2: 'CSAT.STARS.TWO',
  3: 'CSAT.STARS.THREE',
  4: 'CSAT.STARS.FOUR',
  5: 'CSAT.STARS.FIVE',
};

// A chave sai de STAR_LABELS, mapa literal e fechado logo acima. O que o lint
// nao confere aqui esta conferido por teste: o spec do bloco exige as cinco
// chaves presentes em pt_BR E em en.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const labelFor = value => t(STAR_LABELS[value]);

// O grupo tem UM ponto de parada no Tab. Sem seleção, é a primeira estrela.
const focusableValue = computed(() => props.selectedRating || 1);

const onHoverRating = value => {
  if (props.isDisabled) return;
  hoveredRating.value = value;
};

const selectRating = value => {
  if (props.isDisabled) return;
  emit('selectRating', value);
};

const moveFocus = delta => {
  if (props.isDisabled) return;
  const atual = focusableValue.value;
  const proximo = Math.min(5, Math.max(1, atual + delta));
  // Em `radiogroup`, mover o foco com seta TAMBÉM escolhe — é o comportamento
  // esperado do papel, e é o que evita o estado em que a estrela está focada mas
  // não marcada.
  selectRating(proximo);
};

const getStarClass = value => {
  const isStarActive =
    (hoveredRating.value > 0 &&
      !props.isDisabled &&
      hoveredRating.value >= value) ||
    props.selectedRating >= value;

  return isStarActive
    ? 'i-ri-star-fill text-n-amber-9'
    : 'i-ri-star-line text-n-slate-10';
};
</script>

<template>
  <div
    class="flex justify-center py-5 px-4 gap-1"
    role="radiogroup"
    :aria-label="$t('CSAT.RATING_GROUP_LABEL')"
    :aria-disabled="isDisabled ? 'true' : undefined"
    @keydown.right.prevent="moveFocus(1)"
    @keydown.down.prevent="moveFocus(1)"
    @keydown.left.prevent="moveFocus(-1)"
    @keydown.up.prevent="moveFocus(-1)"
  >
    <button
      v-for="value in starRatings"
      :key="value"
      type="button"
      role="radio"
      class="star-rating__opcao rounded-full transition-all duration-200 focus:enabled:scale-[1.2] focus-within:enabled:scale-[1.2] hover:enabled:scale-[1.2] flex items-center justify-center flex-shrink-0"
      :class="{ 'cursor-not-allowed opacity-50': isDisabled }"
      :disabled="isDisabled"
      :aria-checked="selectedRating === value ? 'true' : 'false'"
      :aria-label="labelFor(value)"
      :tabindex="focusableValue === value ? 0 : -1"
      @click="selectRating(value)"
      @mouseenter="onHoverRating(value)"
      @mouseleave="onHoverRating(0)"
    >
      <span
        :class="getStarClass(value)"
        class="transition-all duration-500 text-2xl"
        aria-hidden="true"
      />
    </button>
  </div>
</template>

<style scoped lang="scss">
.star-rating__opcao {
  // SC 2.5.8 — alvo mínimo de 44x44. O ícone continua com 24 px; o que cresce é
  // a área clicável, então nada muda visualmente e o polegar para de errar.
  min-width: 44px;
  min-height: 44px;

  &:focus-visible {
    outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
    outline-offset: var(--w-focus-ring-offset);
  }
}
</style>
