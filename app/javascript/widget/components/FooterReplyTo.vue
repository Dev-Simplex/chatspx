<script>
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

export default {
  name: 'FooterReplyTo',
  components: { FluentIcon },
  props: {
    inReplyTo: {
      type: Object,
      default: () => {},
    },
  },
  emits: ['dismiss'],
  computed: {
    replyToAttachment() {
      if (!this.inReplyTo?.attachments?.length) {
        return '';
      }

      const [{ file_type: fileType } = {}] = this.inReplyTo.attachments;
      return this.$t(`ATTACHMENTS.${fileType}.CONTENT`);
    },
  },
};
</script>

<template>
  <div
    class="mb-2.5 rounded-[7px] bg-n-slate-3 px-2 py-1.5 text-sm text-n-slate-11 flex items-center gap-2"
  >
    <div class="items-center flex-grow truncate">
      <strong>{{ $t('FOOTER_REPLY_TO.REPLY_TO') }}</strong>
      {{ inReplyTo.content || replyToAttachment }}
    </div>
    <!-- Aqui NÃO cabe `aria-labelledby` apontando o texto ao lado, como se fez
         em `RadioCard.vue`: aquele texto é "Respondendo a <mensagem>", que
         nomeia a TIRA, não o botão. Reaproveitá-lo faria o leitor de tela
         anunciar "Respondendo a olá, botão" para um controle que CANCELA a
         resposta. O critério do RadioCard é não duplicar texto que já está na
         tela — e o nome desta ação não está em lugar nenhum da tela, então o
         i18n é a fonte única, não uma segunda cópia. -->
    <button
      class="items-end flex-shrink-0 p-1 rounded-md hover:bg-n-slate-5"
      :title="$t('A11Y.DISMISS_REPLY')"
      :aria-label="$t('A11Y.DISMISS_REPLY')"
      @click="$emit('dismiss')"
    >
      <FluentIcon icon="dismiss" size="12" />
    </button>
  </div>
</template>
