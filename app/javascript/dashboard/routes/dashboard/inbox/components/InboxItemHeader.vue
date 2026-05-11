<script>
import PaginationButton from './PaginationButton.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';

export default {
  components: {
    PaginationButton,
    BackButton,
  },
  props: {
    totalLength: {
      type: Number,
      default: 0,
    },
    currentIndex: {
      type: Number,
      default: 0,
    },
  },
  emits: ['next', 'prev'],
  methods: {
    onClickNext() {
      this.$emit('next');
    },
    onClickPrev() {
      this.$emit('prev');
    },
  },
};
</script>

<template>
  <div
    class="flex items-center justify-between w-full gap-2 border-b px-3 h-12 rtl:border-r border-n-weak flex-shrink-0 bg-n-surface-1"
  >
    <div class="flex items-center gap-4">
      <BackButton
        compact
        :button-label="$t('INBOX.ACTION_HEADER.BACK')"
        class="xl:hidden flex"
      />
      <PaginationButton
        v-if="totalLength > 1"
        :total-length="totalLength"
        :current-index="currentIndex + 1"
        @next="onClickNext"
        @prev="onClickPrev"
      />
    </div>
    <!-- Botões Adiar/Excluir removidos: comportamento WhatsApp-like
         (notificação some automaticamente quando user abre/lê a conversa). -->
    <div />
  </div>
</template>
