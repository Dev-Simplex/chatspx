<script>
/**
 * BLOCO 4.09 — a marcação de SISTEMA de uma troca de atendente.
 *
 * Uma das três marcações do bloco (sistema · header · bolha). Aparece no fluxo da
 * conversa, entre a última fala de quem saiu e a primeira de quem entrou.
 *
 * NUNCA ROXO COMO MARCADOR — e a regra é mais forte do que a cor.
 *
 * O aceite proíbe roxo porque, contra o azul, ele colapsa para ΔE 1,8 em
 * deuteranopia: quem tem essa deficiência vê os dois marcadores como o mesmo.
 * Mas trocar roxo por outra cor só empurra o problema. O que este componente faz
 * é **não usar cor como sinal**: quem distingue "entrou a equipe" de "voltou o
 * assistente" é a FRASE, que é diferente nos dois casos e é lida por leitor de
 * tela, por quem não distingue cor e por quem está no sol.
 *
 * A cor aqui é só fundo neutro (`--w-*` do 1.01), igual nos dois sentidos, e o
 * ícone é decorativo. Um teste em Chromium mede que os dois marcadores têm a
 * MESMA cor computada — se um dia alguém os colorir diferente, o teste reprova.
 */
export default {
  name: 'AiHandoffMark',
  props: {
    /** `to_human` ou `to_ai` — vem de `handoffMarkFor` em `helpers/aiIdentity`. */
    kind: {
      type: String,
      required: true,
      validator: valor => ['to_human', 'to_ai'].includes(valor),
    },
  },
  computed: {
    paraHumano() {
      return this.kind === 'to_human';
    },
  },
};
</script>

<template>
  <div class="ai-handoff-mark" role="status" :data-handoff="kind">
    <span class="ai-handoff-mark__linha" aria-hidden="true" />
    <!--
      Duas chaves LITERAIS em vez de uma interpolada: chave montada em runtime o
      lint de i18n nao consegue conferir, e uma que faltasse viraria texto cru na
      tela do visitante. Escritas assim, as duas sao verificaveis.
    -->
    <span v-if="paraHumano" class="ai-handoff-mark__texto">
      {{ $t('AI_IDENTITY.HANDOFF_TO_HUMAN') }}
    </span>
    <span v-else class="ai-handoff-mark__texto">
      {{ $t('AI_IDENTITY.HANDOFF_TO_AI') }}
    </span>
    <span class="ai-handoff-mark__linha" aria-hidden="true" />
  </div>
</template>

<style scoped lang="scss">
.ai-handoff-mark {
  @apply flex items-center gap-2 my-3 px-2;

  &__linha {
    @apply flex-1 h-px bg-n-weak;
  }

  &__texto {
    // Mesma cor nos DOIS sentidos, de propósito: a diferença entre eles é o
    // texto. Ver o comentário longo no topo do arquivo.
    @apply text-xs text-n-slate-11 text-center;
  }
}
</style>
