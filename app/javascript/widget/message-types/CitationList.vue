<script>
/**
 * As fontes de uma resposta da IA (bloco 6.03).
 *
 * A citação chega em `content_attributes.citations`, gravada pelo servidor a partir do
 * que a busca REALMENTE recuperou — nunca lida do texto do modelo. Aqui só se desenha.
 *
 * Duas decisões que são o bloco:
 *
 * 1. LINK SÓ QUANDO HÁ URL PÚBLICA. Documento interno (PDF/texto colado) aparece como
 *    referência sem href: um link que não abre é pior que nenhum link, e ele levaria a
 *    marca do cliente junto.
 * 2. NOME ACESSÍVEL É TEXTO LIMPO. O título vem do cliente, e cliente põe emoji em nome
 *    de documento. O leitor de tela anunciaria "Abrir o documento fogo Política de
 *    trocas" — o símbolo fica no visível, some do nome. É a mesma regra dos primitivos
 *    do 2.01 (`widget/ui/rotulos.js`), aplicada a dado de runtime em vez de a prop.
 */
const PICTOGRAFICO = /\p{Extended_Pictographic}/gu;

export default {
  name: 'CitationList',
  inheritAttrs: false,
  props: {
    citations: {
      type: Array,
      default: () => [],
    },
  },
  computed: {
    visiveis() {
      return this.citations.filter(citation => citation && citation.title);
    },
  },
  methods: {
    nomeLimpo(titulo) {
      const limpo = String(titulo || '')
        .replace(PICTOGRAFICO, '')
        .replace(/\s+/g, ' ')
        .trim();
      return limpo || this.$t('CITATION.FALLBACK_NAME');
    },
    rotuloDoLink(citation) {
      return this.$t('CITATION.OPEN_LABEL', {
        documento: this.nomeLimpo(citation.title),
      });
    },
  },
};
</script>

<template>
  <div v-if="visiveis.length" class="citation-list">
    <span class="citation-list__label">{{ $t('CITATION.SOURCE') }}</span>
    <ul class="citation-list__items">
      <li v-for="(citation, index) in visiveis" :key="index">
        <a
          v-if="citation.url"
          :href="citation.url"
          :aria-label="rotuloDoLink(citation)"
          :title="citation.excerpt || undefined"
          target="_blank"
          rel="noopener noreferrer"
          class="citation-list__link"
        >
          {{ citation.title }}
        </a>
        <span
          v-else
          class="citation-list__text"
          :aria-label="nomeLimpo(citation.title)"
          :title="citation.excerpt || undefined"
        >
          {{ citation.title }}
        </span>
      </li>
    </ul>
  </div>
</template>

<style scoped lang="scss">
.citation-list {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 0.25rem 0.375rem;
  margin-top: 0.25rem;
  font-size: 0.6875rem;
  line-height: 1.4;
  color: rgb(var(--slate-11));
}

.citation-list__label {
  font-weight: 600;
}

.citation-list__items {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem 0.5rem;
  margin: 0;
  padding: 0;
  list-style: none;
}

.citation-list__link {
  color: rgb(var(--slate-12));
  text-decoration: underline;
}

.citation-list__link:hover {
  text-decoration: none;
}
</style>
