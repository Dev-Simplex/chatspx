<script>
/**
 * Estado vazio — o 14º primitivo de `widget/ui/` (blocos 2.01 e 2.07).
 *
 * «Vazio» é um dos cinco estados de verdade do bloco 2.07, e era o único sem
 * desenho nenhum: uma conversa recém-criada mostrava uma superfície texturizada
 * em branco, indistinguível de uma conversa que falhou ao carregar.
 *
 * A REGRA DE ACESSIBILIDADE que este componente carrega no lugar de cada
 * consumidor: o pictograma é `aria-hidden`. Ele vive dentro de regiões com
 * `role="log"` (a lista de mensagens), onde tudo que não é escondido é lido em
 * voz alta — e um SVG anunciado no meio do histórico é ruído. Quem informa é o
 * TEXTO, que por isso é obrigatório e não um slot opcional.
 *
 * `title`/`body` como props e não como slots: um estado vazio sem texto é o
 * defeito que este componente existe para impedir, e prop com `required`
 * reprova na hora em que alguém tenta.
 */
export default {
  name: 'WEmptyState',
  props: {
    /** A frase curta. Obrigatória: vazio sem texto é o defeito original. */
    title: {
      type: String,
      required: true,
      validator: valor => typeof valor === 'string' && valor.trim().length > 0,
    },
    /** A explicação. Opcional — nem todo vazio precisa de duas frases. */
    body: { type: String, default: '' },
  },
};
</script>

<template>
  <div class="w-empty-state">
    <div v-if="$slots.icone" class="w-empty-state__icone" aria-hidden="true">
      <slot name="icone" />
    </div>
    <p class="w-empty-state__titulo">{{ title }}</p>
    <p v-if="body" class="w-empty-state__corpo">{{ body }}</p>
  </div>
</template>

<style scoped lang="scss">
.w-empty-state {
  @apply flex flex-col items-center justify-center gap-1 px-6 py-8 text-center;

  &__icone {
    @apply mb-1 text-n-slate-10;
  }

  &__titulo {
    @apply text-sm font-medium text-n-slate-12;
  }

  &__corpo {
    // `max-w` em ch para a linha quebrar por MEDIDA de leitura, não pela
    // largura do painel: o widget vive entre 320 e 400 px, e sem teto a frase
    // vira uma coluna de duas palavras no celular.
    @apply text-xs leading-5 text-n-slate-11 max-w-[34ch];
  }
}
</style>
