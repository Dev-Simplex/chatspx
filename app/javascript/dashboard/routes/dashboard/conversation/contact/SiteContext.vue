<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactDetailsItem from '../ContactDetailsItem.vue';
import {
  contactOriginKeys,
  conversationOriginKeys,
  ORIGIN_KINDS,
} from 'dashboard/helper/originAttributes';

/**
 * Bloco 5.23 — **o que o site nos contou**, numa seção própria.
 *
 * ── O PROBLEMA QUE ELA RESOLVE ──────────────────────────────────────────────────────────
 *
 * A origem (1.19), os atributos que o site provisionou (1.17) e o que o AGENTE digitou caem
 * todos na mesma lista de atributos personalizados, em ordem alfabética de definição. Para
 * responder *"de onde veio esta pessoa"* o agente rola a barra inteira e ainda precisa saber,
 * de cabeça, quais chaves são de origem. Aqui as duas perguntas — de onde veio, e o que o site
 * já sabe dela — ficam juntas, no topo, e separadas do que foi digitado por gente.
 *
 * ── NENHUM REQUEST NOVO ─────────────────────────────────────────────────────────────────
 *
 * Tudo aqui já chega: `custom_attributes` do contato e da conversa vêm no payload da conversa,
 * e os RÓTULOS vêm das `CustomAttributeDefinition` que a store de atributos já carregou — já
 * traduzidos pelo servidor (`config/locales/tracking_origin.*.yml`, bloco 1.18). O front não
 * tem uma segunda tabela de rótulos, e por isso não há como os dois nomes divergirem.
 *
 * ── AUSÊNCIA TEM NOME (regra do 1.19) ───────────────────────────────────────────────────
 *
 * Chave sem valor não vira linha. Mas `origin_kind` com `nao_disponivel` **é** um valor, e
 * aparece dizendo isso: "não disponível". Chamar ausência de "origem direta" é a mentira que o
 * 1.22 proibiu no relatório, e ela começaria aqui se a linha simplesmente sumisse.
 *
 * Com zero linhas em tudo, o componente **não renderiza** — o `AccordionItem` que o envolve
 * some junto. Seção vazia é pior que seção ausente: ocupa espaço prometendo dado.
 */
const props = defineProps({
  /** `custom_attributes` do contato — as chaves `first_*`. */
  contactAttributes: { type: Object, default: () => ({}) },
  /** `custom_attributes` da conversa — as chaves `last_*`. */
  conversationAttributes: { type: Object, default: () => ({}) },
  /** As `CustomAttributeDefinition` já carregadas, de onde saem os rótulos traduzidos. */
  definitions: { type: Array, default: () => [] },
  /** O contato foi identificado pelo site (`setUser`)? */
  identifier: { type: String, default: '' },
  /** A identificação veio assinada (HMAC/JWT verificado)? Bloco 4.15. */
  hmacVerified: { type: Boolean, default: false },
});

const { t } = useI18n();

const rotulos = computed(() =>
  props.definitions.reduce((acc, definicao) => {
    if (definicao?.attribute_key)
      acc[definicao.attribute_key] = definicao.attribute_display_name;
    return acc;
  }, {})
);

/**
 * O valor de `origin_kind` é vocabulário fechado do servidor (`ORIGIN_KINDS`) e precisa de
 * tradução no navegador — o servidor traduz o RÓTULO da definição, não o valor gravado.
 *
 * Valor fora da lista sai CRU, de propósito: um `origin_kind` novo que o servidor passe a
 * gravar antes de o front conhecê-lo aparece como está, em vez de sumir. Dado estranho na tela
 * é um bug visível; dado que some é um bug que ninguém abre.
 */
const traduzValor = (chave, valor) => {
  if (!chave.endsWith('origin_kind')) return valor;
  if (!ORIGIN_KINDS.includes(valor)) return valor;

  return t(`CONTACT_PANEL.SITE_CONTEXT.ORIGIN_KIND.${valor.toUpperCase()}`);
};

const linhas = (atributos, chaves) =>
  chaves
    .filter(chave => {
      const valor = atributos?.[chave];
      return valor !== undefined && valor !== null && valor !== '';
    })
    .map(chave => ({
      key: chave,
      // Sem definição carregada, o rótulo é a própria chave — nunca uma tradução inventada
      // aqui, que divergiria da que o servidor já escolheu.
      title: rotulos.value[chave] || chave,
      value: String(traduzValor(chave, atributos[chave])),
    }));

const linhasDoContato = computed(() =>
  linhas(props.contactAttributes, contactOriginKeys())
);
const linhasDaConversa = computed(() =>
  linhas(props.conversationAttributes, conversationOriginKeys())
);

/**
 * A identidade só vira linha quando o site DE FATO identificou alguém. Visitante anônimo é o
 * caso normal e não merece uma linha dizendo "não identificado" em toda conversa — isso é
 * ruído, não informação. Ver a diferença com `origin_kind`, que é um dado que o servidor
 * gravou e por isso é dito mesmo quando é ausência.
 */
const linhaDeIdentidade = computed(() => {
  if (!props.identifier) return null;

  return {
    title: t('CONTACT_PANEL.SITE_CONTEXT.IDENTIFIED_AS'),
    value: props.identifier,
    verificado: props.hmacVerified,
  };
});

const temAlgo = computed(
  () =>
    linhasDoContato.value.length > 0 ||
    linhasDaConversa.value.length > 0 ||
    linhaDeIdentidade.value !== null
);
</script>

<template>
  <div
    v-if="temAlgo"
    class="flex flex-col gap-3 pb-1"
    data-testid="site-context"
  >
    <!--
      O selo aparece UMA vez, no topo da seção, e não por linha: aqui dentro tudo veio do site,
      então repeti-lo em cada item seria ruído. É o oposto da seção do 1.17, onde os atributos
      do site convivem com os do agente na mesma lista e o selo precisa ser por item.
    -->
    <span
      class="self-start px-1.5 py-0.5 text-xs rounded bg-n-slate-3 text-n-slate-12"
      :title="$t('CONTACT_PANEL.SITE_CONTEXT.BADGE_TITLE')"
      data-testid="site-context-badge"
    >
      {{ $t('CONTACT_PANEL.SITE_CONTEXT.BADGE') }}
    </span>

    <div v-if="linhasDoContato.length" data-testid="site-context-first">
      <h4 class="mb-1 text-sm font-medium text-n-slate-12">
        {{ $t('CONTACT_PANEL.SITE_CONTEXT.FIRST_TOUCH') }}
      </h4>
      <ContactDetailsItem
        v-for="linha in linhasDoContato"
        :key="linha.key"
        :title="linha.title"
        :value="linha.value"
      />
    </div>

    <div v-if="linhasDaConversa.length" data-testid="site-context-last">
      <h4 class="mb-1 text-sm font-medium text-n-slate-12">
        {{ $t('CONTACT_PANEL.SITE_CONTEXT.THIS_CONVERSATION') }}
      </h4>
      <ContactDetailsItem
        v-for="linha in linhasDaConversa"
        :key="linha.key"
        :title="linha.title"
        :value="linha.value"
      />
    </div>

    <div v-if="linhaDeIdentidade" data-testid="site-context-identity">
      <h4 class="mb-1 text-sm font-medium text-n-slate-12">
        {{ $t('CONTACT_PANEL.SITE_CONTEXT.IDENTITY') }}
      </h4>
      <ContactDetailsItem
        :title="linhaDeIdentidade.title"
        :value="linhaDeIdentidade.value"
      />
      <!--
        Assinatura verificada é o que separa "o site disse que é a Ana" de "o site PROVOU que é
        a Ana" (bloco 4.15). Sem HMAC/JWT, qualquer visitante pode chamar `setUser` com o
        identificador de outro — e o agente precisa saber em qual dos dois casos está.
      -->
      <ContactDetailsItem
        :title="$t('CONTACT_PANEL.SITE_CONTEXT.SIGNATURE')"
        :value="
          linhaDeIdentidade.verificado
            ? $t('CONTACT_PANEL.SITE_CONTEXT.SIGNATURE_VERIFIED')
            : $t('CONTACT_PANEL.SITE_CONTEXT.SIGNATURE_ABSENT')
        "
      />
    </div>
  </div>
</template>
