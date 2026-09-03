<script>
import CardButton from 'shared/components/CardButton.vue';

/**
 * BLOCO 4.10 — teto de TRES botoes por card.
 *
 * O aceite do bloco fixa o numero, e a razao e de leitura, nao de estetica: o
 * card e uma bolha estreita (`max-w-56`, 224 px) dentro de um painel de 400. Com
 * quatro ou mais acoes empilhadas, a decisao deixa de ser uma escolha e vira uma
 * lista para ler — e quem esta em duvida no meio de um atendimento nao le lista.
 *
 * O corte e do CONSUMIDOR de proposito. O servidor pode mandar quantas acoes
 * quiser (e outros canais renderizam o mesmo payload com outras regras); quem
 * limita e quem desenha. Cortar aqui tambem significa que uma automacao mal
 * configurada nao deforma a bolha do visitante.
 */
export const MAX_CARD_ACTIONS = 3;

export default {
  components: {
    CardButton,
  },
  props: {
    title: {
      type: String,
      default: '',
    },
    description: {
      type: String,
      default: '',
    },
    mediaUrl: {
      type: String,
      default: '',
    },
    actions: {
      type: Array,
      default: () => [],
    },
  },
  computed: {
    visibleActions() {
      return (this.actions || []).slice(0, MAX_CARD_ACTIONS);
    },
  },
};
</script>

<template>
  <div
    class="card-message chat-bubble agent bg-n-background dark:bg-n-solid-3 max-w-56 rounded-lg overflow-hidden"
  >
    <!--
      A imagem do card e DECORATIVA: o titulo e a descricao logo abaixo dizem a
      mesma coisa em texto. Sem `alt`, o leitor de tela le a URL do arquivo, que
      e ruido; com `alt` vazio e `aria-hidden`, ele pula direto para o conteudo.
      So renderiza quando ha URL — `<img>` sem `src` desenha icone de quebrado.
    -->
    <img
      v-if="mediaUrl"
      class="w-full object-contain max-h-[150px] rounded-[5px]"
      :src="mediaUrl"
      alt=""
      aria-hidden="true"
    />
    <div class="card-body">
      <h4
        class="!text-base !font-medium !mt-1 !mb-1 !leading-[1.5] text-n-slate-12"
      >
        {{ title }}
      </h4>
      <p class="!mb-1 text-n-slate-11">
        {{ description }}
      </p>
      <CardButton
        v-for="action in visibleActions"
        :key="action.id"
        :action="action"
      />
    </div>
  </div>
</template>
