<script>
import Spinner from 'shared/components/Spinner.vue';
import { CSAT_RATINGS, CSAT_DISPLAY_TYPES } from 'shared/constants/messages';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import StarRating from 'shared/components/StarRating.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

export default {
  components: {
    Spinner,
    FluentIcon,
    StarRating,
  },
  props: {
    messageContentAttributes: {
      type: Object,
      default: () => {},
    },
    messageId: {
      type: Number,
      required: true,
    },
    displayType: {
      type: String,
      default: CSAT_DISPLAY_TYPES.EMOJI,
    },
    message: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { formatMessage } = useMessageFormatter();
    return { formatMessage };
  },
  data() {
    return {
      email: '',
      ratings: CSAT_RATINGS,
      selectedRating: null,
      isUpdating: false,
      feedback: '',
    };
  },
  computed: {
    isRatingSubmitted() {
      return this.messageContentAttributes?.csat_survey_response?.rating;
    },
    isFeedbackSubmitted() {
      return this.messageContentAttributes?.csat_survey_response
        ?.feedback_message;
    },
    isLocked() {
      return !!(this.isFeedbackSubmitted || this.isUpdating);
    },
    // O grupo tem UM ponto de parada no Tab; sem escolha, e a primeira opcao.
    focusableRating() {
      return this.selectedRating || this.ratings[0]?.value;
    },
    isButtonDisabled() {
      if (!(this.selectedRating && this.feedback)) return true;
      if (this.isUpdating) return true;
      return false;
    },
    title() {
      return this.isRatingSubmitted
        ? this.$t('CSAT.SUBMITTED_TITLE')
        : this.message || this.$t('CSAT.TITLE');
    },
    formattedTitle() {
      return this.formatMessage(this.title, false);
    },
    isEmojiType() {
      return this.displayType === CSAT_DISPLAY_TYPES.EMOJI;
    },
    isStarType() {
      return this.displayType === CSAT_DISPLAY_TYPES.STAR;
    },
  },

  mounted() {
    if (this.isRatingSubmitted) {
      const {
        csat_survey_response: { rating, feedback_message },
      } = this.messageContentAttributes;
      this.selectedRating = rating;
      this.feedback = feedback_message;
    }
  },

  methods: {
    buttonClass(rating) {
      return [
        { selected: rating.value === this.selectedRating },
        { disabled: this.isLocked },
        { hover: this.isLocked },
        'emoji-button',
      ];
    },
    /**
     * Bloco 4.10 — o rotulo TEXTUAL da opcao.
     *
     * `translationKey` sai da constante `CSAT_RATINGS`, que e literal e fechada:
     * as cinco chaves estao escritas la, nao montadas aqui. O teste do bloco
     * exige as cinco presentes em pt_BR E em en — o componente e compartilhado
     * com o dashboard, e as chaves existiam so num dos dois bundles.
     */
    ratingLabel(rating) {
      // A chave sai de CSAT_RATINGS, constante literal e fechada em
      // `shared/constants/messages.js`. O que o lint nao consegue conferir aqui
      // esta conferido por TESTE: o spec do bloco exige as cinco chaves em pt_BR
      // E em en — elas existiam so no bundle do dashboard, e o componente e
      // compartilhado com o widget.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      return this.$t(rating.translationKey);
    },
    /**
     * Setas escolhem, e nao so movem o foco: e o comportamento do papel
     * `radiogroup`, e e o que evita o estado em que a opcao esta focada mas nao
     * marcada — que para o leitor de tela e indistinguivel de nada ter acontecido.
     */
    moveRatingFocus(delta) {
      if (this.isLocked) return;
      const indiceAtual = this.ratings.findIndex(
        rating => rating.value === this.focusableRating
      );
      const proximo =
        this.ratings[
          Math.min(this.ratings.length - 1, Math.max(0, indiceAtual + delta))
        ];
      if (proximo) this.selectRating(proximo);
    },
    async onSubmit() {
      if (this.isUpdating) return;
      this.isUpdating = true;
      try {
        await this.$store.dispatch('message/update', {
          submittedValues: {
            csat_survey_response: {
              rating: this.selectedRating,
              feedback_message: this.feedback,
            },
          },
          messageId: this.messageId,
        });
      } catch (error) {
        // Ignore error
      } finally {
        this.isUpdating = false;
      }
    },

    selectRating(rating) {
      if (this.isFeedbackSubmitted || this.isUpdating) return;
      this.selectedRating = rating.value;
      this.onSubmit();
    },
    selectStarRating(value) {
      if (this.isFeedbackSubmitted || this.isUpdating) return;
      this.selectedRating = value;
      this.onSubmit();
    },
  },
};
</script>

<template>
  <div
    class="customer-satisfaction w-full bg-n-background dark:bg-n-solid-3 shadow-[0_0.25rem_6px_rgba(50,50,93,0.08),0_1px_3px_rgba(0,0,0,0.05)] ltr:rounded-bl-[0.25rem] rtl:rounded-br-[0.25rem] rounded-lg inline-block leading-[1.5] mt-1 border-t-2 border-t-w-brand-readable border-solid"
  >
    <h6
      v-dompurify-html="formattedTitle"
      class="text-n-slate-12 text-sm font-medium pt-5 px-2.5 text-center csat-title"
    />
    <!--
      Bloco 4.10 — os cinco emojis viram um grupo de radio.

      Antes eram cinco <button> cujo conteudo era SO o emoji: o leitor de tela
      anunciava o simbolo, nao "Ruim", e nao dizia que escolher um desmarca os
      outros. O rotulo textual ja existia em CSAT_RATINGS[].translationKey e
      ninguem o usava — ver a nota do relatorio sobre a chave que existia num
      bundle so.
    -->
    <div
      v-if="isEmojiType"
      class="ratings flex justify-around py-5 px-4"
      role="radiogroup"
      :aria-label="$t('CSAT.RATING_GROUP_LABEL')"
      :aria-disabled="isLocked ? 'true' : undefined"
      @keydown.right.prevent="moveRatingFocus(1)"
      @keydown.down.prevent="moveRatingFocus(1)"
      @keydown.left.prevent="moveRatingFocus(-1)"
      @keydown.up.prevent="moveRatingFocus(-1)"
    >
      <button
        v-for="rating in ratings"
        :key="rating.key"
        type="button"
        role="radio"
        :class="buttonClass(rating)"
        :disabled="isLocked"
        :aria-checked="rating.value === selectedRating ? 'true' : 'false'"
        :aria-label="ratingLabel(rating)"
        :tabindex="focusableRating === rating.value ? 0 : -1"
        @click="selectRating(rating)"
      >
        <span aria-hidden="true">{{ rating.emoji }}</span>
      </button>
    </div>
    <StarRating
      v-else-if="isStarType"
      :selected-rating="selectedRating"
      :is-disabled="isFeedbackSubmitted || isUpdating"
      @select-rating="selectStarRating"
    />
    <form
      v-if="!isFeedbackSubmitted"
      class="feedback-form flex"
      @submit.prevent="onSubmit()"
    >
      <input
        v-model="feedback"
        :placeholder="$t('CSAT.PLACEHOLDER')"
        @keydown.enter="onSubmit"
      />
      <button class="button small" :disabled="isButtonDisabled">
        <Spinner v-if="isUpdating && feedback" />
        <FluentIcon v-else icon="chevron-right" />
      </button>
    </form>
  </div>
</template>

<style lang="scss" scoped>
// Bloco 1.08 — este título usava `prose prose-bubble`, e era a ÚNICA ocorrência
// de `prose` em tudo que o widget renderiza. O plugin `@tailwindcss/typography`
// cobrava 16.536 B no CSS do widget por ela: estilos para h1–h6, listas,
// tabelas, `pre`, `blockquote` e imagens, num título de uma linha.
//
// O conteúdo aqui é markdown sanitizado (`v-dompurify-html`), e o que de fato
// aparece num título de pesquisa é ênfase, link e, no limite, código inline. É
// isso que está estilizado abaixo — o resto herda, como já herdava.
.csat-title {
  line-height: 1.6;

  :deep(p) {
    @apply m-0;

    & + p {
      @apply mt-1;
    }
  }

  :deep(strong),
  :deep(b) {
    @apply font-bold text-n-slate-12;
  }

  :deep(em),
  :deep(i) {
    @apply italic;
  }

  :deep(a) {
    @apply underline text-w-brand-readable;
  }

  :deep(code) {
    @apply bg-n-alpha-2 text-n-slate-11 rounded px-1 py-px text-xs;
  }
}

.customer-satisfaction {
  .ratings {
    .emoji-button {
      @apply shadow-none grayscale text-2xl transition-all duration-200
        inline-flex items-center justify-center;

      // Bloco 4.10 — SC 2.5.8: alvo minimo de 44x44. O emoji continua com 24 px;
      // o que cresce e a area clicavel, entao nada muda visualmente e o polegar
      // para de errar a carinha vizinha.
      min-width: 44px;
      min-height: 44px;

      // O `outline-none` de antes apagava o anel de foco do teclado — num
      // controle que agora e `radiogroup`, isso deixaria quem navega por teclado
      // sem saber em que opcao esta. O anel sai dos tokens da inbox.
      &:focus-visible {
        outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
        outline-offset: var(--w-focus-ring-offset);
      }

      &.selected,
      &:hover,
      &:focus,
      &:active {
        @apply grayscale-0 scale-[1.32];
      }

      &.disabled {
        @apply cursor-not-allowed opacity-50 pointer-events-none;
      }
    }
  }

  .feedback-form {
    input {
      @apply h-10 dark:bg-n-alpha-black1 rtl:rounded-tl-[0] rtl:rounded-tr-[0] ltr:rounded-tr-[0] ltr:rounded-tl-[0] rtl:rounded-bl-[0] ltr:rounded-br-[0] ltr:rounded-bl-[0.25rem] rtl:rounded-br-[0.25rem] rounded-lg p-2.5 w-full focus:ring-0 focus:outline-w-focus;

      &::placeholder {
        @apply text-n-slate-10;
      }
    }

    .button {
      @apply rtl:rounded-tr-[0] rtl:rounded-tl-[0] appearance-none ltr:rounded-tl-[0] ltr:rounded-tr-[0] rtl:rounded-br-[0] ltr:rounded-bl-[0] rounded-lg h-auto ltr:-ml-px rtl:-mr-px text-xl;

      .spinner {
        display: block;
        padding: 0;
        height: auto;
        width: auto;
      }
    }
  }
}
</style>
