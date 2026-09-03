<script>
/**
 * Bloco 2.03 — o horário SAIU daqui.
 *
 * Ele era um `<span class="time">` posicionado em absoluto sobre o canto da
 * imagem, dentro do balão, com um degradê escuro (`::before`) desenhado só para
 * torná-lo legível. O bloco 2.03 tira o horário de dentro do balão — e, sem o
 * horário, o degradê não tem mais o que proteger: ele escurecia 20% de toda
 * imagem enviada em troca de nada.
 *
 * Quem desenha o horário agora é a linha da mensagem (`.message-time` em
 * `AgentMessage.vue`/`UserMessage.vue`), FORA do balão.
 */
export default {
  props: {
    url: { type: String, default: '' },
    thumb: { type: String, default: '' },
  },
  emits: ['error'],
  methods: {
    onImgError() {
      this.$emit('error');
    },
  },
};
</script>

<template>
  <a
    :href="url"
    target="_blank"
    rel="noreferrer noopener nofollow"
    class="image"
  >
    <div class="wrap">
      <img
        :src="thumb"
        :alt="$t('A11Y.IMAGE_ATTACHMENT')"
        @error="onImgError"
      />
    </div>
  </a>
</template>

<style lang="scss" scoped>
.image {
  display: block;

  .wrap {
    display: flex;
    max-width: 100%;
  }

  img {
    width: 100%;
    max-width: 250px;
  }
}
</style>
