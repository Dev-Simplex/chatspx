<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

// Produto do catálogo enviado na conversa (C8).
//
// A bolha se reconstrói do `content_attributes`, e NÃO do produto no banco: quem abre a conversa
// em janeiro tem de ver o preço que foi ofertado em setembro, mesmo que o produto tenha mudado de
// preço ou saído do catálogo. Por isso o retrato viaja gravado na mensagem.
//
// A foto também vai como anexo da mensagem — é o que faz o cliente receber a imagem no WhatsApp.
// Aqui usamos a capa do retrato para desenhar o card, então a mesma foto não aparece duas vezes.
const { t } = useI18n();
const { contentAttributes, id } = useMessageContext();

const produtos = computed(() => contentAttributes.value?.catalogProducts ?? []);

const emPromocao = produto =>
  produto.promoPriceCents && produto.promoPriceCents < produto.priceCents;

const dinheiro = (centavos, moeda) =>
  ((centavos ?? 0) / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: moeda || 'BRL',
  });
</script>

<template>
  <BaseBubble class="overflow-hidden">
    <ul class="flex flex-col gap-2 m-0 p-0 list-none">
      <li
        v-for="(produto, indice) in produtos"
        :key="`${id}-produto-${produto.id ?? indice}`"
        class="flex gap-2.5 p-1.5 rounded-lg bg-[var(--wa-card-bg)] dark:bg-[var(--wa-card-bg-dark)]"
      >
        <img
          v-if="produto.coverUrl"
          :src="produto.coverUrl"
          :alt="produto.name"
          class="size-16 rounded-md object-cover flex-none"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <span class="font-medium break-words">{{ produto.name }}</span>
          <span class="flex items-baseline gap-1.5">
            <span class="font-medium">
              {{ dinheiro(produto.currentPriceCents, produto.currency) }}
            </span>
            <span
              v-if="emPromocao(produto)"
              class="text-sm line-through opacity-60"
            >
              {{ dinheiro(produto.priceCents, produto.currency) }}
            </span>
          </span>
          <span
            v-if="produto.description"
            class="text-sm opacity-80 break-words"
          >
            {{ produto.description }}
          </span>
          <span v-if="produto.sku" class="text-sm opacity-60">
            {{ t('COMPONENTS.CATALOG_BUBBLE.SKU', { sku: produto.sku }) }}
          </span>
        </div>
      </li>
    </ul>
  </BaseBubble>
</template>
