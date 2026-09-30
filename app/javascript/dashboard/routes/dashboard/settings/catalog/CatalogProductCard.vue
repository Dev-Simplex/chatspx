<script setup>
import { computed } from 'vue';
import { formatarPreco } from './catalogoPreco';
import CatalogMetaBadge from './CatalogMetaBadge.vue';

const props = defineProps({
  produto: {
    type: Object,
    required: true,
  },
  // Conta sem espelho configurado não mostra selo: todo produto ficaria "pendente" para sempre.
  metaSyncEnabled: {
    type: Boolean,
    default: false,
  },
});

// Mandar produto na conversa é pelo seletor do próprio chat (C8); aqui o card só abre o cadastro.
defineEmits(['abrir']);

// `current_price_cents` já vem resolvido pelo backend (promoção vence o cheio). O preço cheio só
// aparece riscado quando há promoção de verdade — repetir o mesmo valor riscado confunde.
const precoAtual = computed(() =>
  formatarPreco(props.produto.current_price_cents, props.produto.currency)
);

const precoCheio = computed(() =>
  props.produto.on_sale
    ? formatarPreco(props.produto.price_cents, props.produto.currency)
    : ''
);

// Estoque zero é diferente de estoque não controlado: o primeiro vira alerta vermelho, o segundo
// simplesmente não mostra etiqueta.
const temEstoque = computed(
  () => props.produto.stock !== null && props.produto.stock !== undefined
);
const semEstoque = computed(
  () => temEstoque.value && props.produto.stock === 0
);
</script>

<template>
  <div
    class="relative flex flex-col overflow-hidden transition-shadow border rounded-xl border-n-weak bg-n-solid-1 hover:shadow-md dark:bg-n-solid-2"
  >
    <div
      class="relative grid w-full place-items-center aspect-square bg-n-slate-3 dark:bg-n-solid-3"
    >
      <img
        v-if="produto.cover_url"
        :src="produto.cover_url"
        :alt="produto.name"
        class="object-cover w-full h-full"
      />
      <span
        v-else
        class="i-lucide-image size-10 text-n-slate-10"
        :title="$t('CATALOG_MGMT.CARD.NO_IMAGE')"
      />
      <div
        class="absolute flex flex-col items-start gap-1 top-2 ltr:left-2 rtl:right-2"
      >
        <span
          v-if="produto.featured"
          class="px-2 py-1 rounded-md text-label-small bg-n-amber-3 text-n-amber-11"
        >
          {{ $t('CATALOG_MGMT.CARD.FEATURED') }}
        </span>
        <span
          v-if="!produto.visible"
          class="px-2 py-1 rounded-md text-label-small bg-n-slate-4 text-n-slate-11"
        >
          {{ $t('CATALOG_MGMT.CARD.HIDDEN') }}
        </span>
        <span
          v-if="temEstoque"
          data-testid="selo-estoque"
          class="px-2 py-1 rounded-md text-label-small"
          :class="
            semEstoque
              ? 'bg-n-ruby-3 text-n-ruby-11'
              : 'bg-n-solid-1 text-n-slate-11 dark:bg-n-solid-2'
          "
        >
          {{
            semEstoque
              ? $t('CATALOG_MGMT.CARD.OUT_OF_STOCK')
              : $t('CATALOG_MGMT.CARD.STOCK', { n: produto.stock })
          }}
        </span>
      </div>
      <CatalogMetaBadge
        v-if="metaSyncEnabled && produto.meta_status"
        :produto="produto"
        class="absolute z-20 top-2 ltr:right-2 rtl:left-2"
      />
    </div>
    <div class="flex flex-col gap-1 p-3">
      <span class="font-medium line-clamp-2 text-n-slate-12 text-body-main">
        {{ produto.name }}
      </span>
      <span class="flex flex-wrap items-baseline gap-1.5">
        <span class="font-semibold text-n-teal-11">{{ precoAtual }}</span>
        <span
          v-if="precoCheio"
          class="line-through text-n-slate-10 text-label-small"
        >
          {{ precoCheio }}
        </span>
      </span>
      <span v-if="produto.sku" class="text-n-slate-10 text-label-small">
        {{ produto.sku }}
      </span>
    </div>
    <!-- O card inteiro abre o cadastro. Botão sobreposto em vez de `@click` na div para o teclado
         chegar no card do mesmo jeito que o mouse — e para não aninhar botão dentro de botão. -->
    <button
      type="button"
      data-testid="abrir-produto"
      class="absolute inset-0 z-10"
      :aria-label="produto.name"
      @click="$emit('abrir', produto)"
    />
  </div>
</template>
