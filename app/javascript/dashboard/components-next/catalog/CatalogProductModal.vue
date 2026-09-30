<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CatalogAPI from 'dashboard/api/catalog';
import { useCatalogLabels } from 'dashboard/composables/useCatalogLabels';

const props = defineProps({
  show: { type: Boolean, default: false },
  // Caixa WAHA não tem catálogo nativo: o produto chega como foto com legenda. O atendente
  // precisa saber disso ANTES de mandar — esconder vira reclamação depois.
  isWaha: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'send']);

const { t } = useI18n();
const { labels, isFieldHidden } = useCatalogLabels();

const dialogRef = ref(null);
const busca = ref('');
const produtos = ref([]);
const carregando = ref(false);
const selecionados = ref([]);
let buscaAbort = null;

const buscar = async termo => {
  if (buscaAbort) buscaAbort.abort();
  buscaAbort = new AbortController();
  carregando.value = true;
  try {
    const { data } = await CatalogAPI.search({ q: (termo || '').trim() });
    produtos.value = data?.payload || [];
  } catch {
    produtos.value = [];
  } finally {
    carregando.value = false;
  }
};

let debounce = null;
watch(busca, termo => {
  clearTimeout(debounce);
  debounce = setTimeout(() => buscar(termo), 300);
});

watch(
  () => props.show,
  aberto => {
    if (!aberto) return;
    selecionados.value = [];
    busca.value = '';
    buscar('');
    nextTick(() => dialogRef.value?.focus());
  }
);

onMounted(() => {
  if (props.show) buscar('');
});

const alternar = id => {
  const i = selecionados.value.indexOf(id);
  if (i === -1) selecionados.value.push(id);
  else selecionados.value.splice(i, 1);
};

const estaSelecionado = id => selecionados.value.includes(id);
const podeEnviar = computed(() => selecionados.value.length > 0);

// O álbum com menu numerado só existe a partir do segundo produto — é o aviso que muda de texto.
const avisoWaha = computed(() =>
  selecionados.value.length > 1
    ? t('CONVERSATION.CATALOG.WAHA_NOTICE_MANY')
    : t('CONVERSATION.CATALOG.WAHA_NOTICE_ONE')
);

// Item sem preço não mostra preço: devolver '' é o que tira a linha do card.
const preco = produto => {
  const centavos = produto.currentPriceCents ?? produto.current_price_cents;
  if (centavos === null || centavos === undefined) return '';

  return (centavos / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
};

const emPromocao = produto => produto.onSale ?? produto.on_sale;

const precoCheio = produto => {
  const valor = produto.priceCents ?? produto.price_cents;
  return (valor / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
};

const capa = produto => produto.coverUrl ?? produto.cover_url;

const fechar = () => emit('close');

const enviar = () => {
  if (!podeEnviar.value) return;
  emit('send', [...selecionados.value]);
};

const onKeyDown = evento => {
  if (evento.key === 'Escape') fechar();
};
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        ref="dialogRef"
        role="dialog"
        aria-modal="true"
        tabindex="-1"
        class="fixed inset-0 z-[1000] flex items-start justify-center px-4 pt-[10vh] pb-8 bg-n-alpha-black1 backdrop-blur-[4px]"
        @click="fechar"
        @keydown="onKeyDown"
      >
        <div
          class="w-full max-w-2xl flex flex-col bg-n-solid-1 dark:bg-[#233138] border border-n-slate-3 dark:border-n-slate-7 rounded-xl shadow-[0_8px_32px_rgba(11,20,26,0.18)] overflow-hidden max-h-[80vh]"
          @click.stop
        >
          <header
            class="flex items-center justify-between px-5 py-4 border-b border-n-slate-3 dark:border-n-slate-7"
          >
            <h3 class="text-base font-medium text-n-slate-12 m-0">
              {{ t('CONVERSATION.CATALOG.TITLE', labels) }}
            </h3>
            <button
              class="reset-base p-1 rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="t('CONVERSATION.CATALOG.CLOSE')"
              @click="fechar"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </header>

          <div class="px-5 pt-4">
            <input
              v-model="busca"
              type="search"
              class="reset-base w-full h-10 px-3 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12 placeholder:text-n-slate-10"
              :placeholder="
                isFieldHidden('sku')
                  ? t('CATALOG_MGMT.SEARCH_PLACEHOLDER_NO_SKU')
                  : t('CONVERSATION.CATALOG.SEARCH')
              "
            />
          </div>

          <div class="flex-1 min-h-0 overflow-y-auto px-5 py-4">
            <p v-if="carregando" class="text-sm text-n-slate-11 m-0">
              {{ t('CONVERSATION.CATALOG.LOADING') }}
            </p>
            <p
              v-else-if="!produtos.length"
              class="text-sm text-n-slate-11 m-0 text-center py-6"
            >
              {{ t('CONVERSATION.CATALOG.EMPTY') }}
            </p>
            <div v-else class="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <button
                v-for="produto in produtos"
                :key="produto.id"
                type="button"
                class="reset-base text-start rounded-lg overflow-hidden outline outline-1 transition-colors"
                :class="
                  estaSelecionado(produto.id)
                    ? 'outline-n-brand bg-n-alpha-2'
                    : 'outline-n-weak hover:bg-n-alpha-1'
                "
                @click="alternar(produto.id)"
              >
                <img
                  v-if="capa(produto)"
                  :src="capa(produto)"
                  :alt="produto.name"
                  class="w-full h-28 object-cover"
                />
                <div
                  v-else
                  class="w-full h-28 flex items-center justify-center bg-n-alpha-1 text-n-slate-10"
                >
                  <span class="i-lucide-image size-6" />
                </div>
                <div class="p-2 flex flex-col gap-0.5">
                  <span class="text-sm text-n-slate-12 line-clamp-2">
                    {{ produto.name }}
                  </span>
                  <span
                    v-if="preco(produto)"
                    class="text-sm text-n-slate-12 font-medium"
                  >
                    {{ preco(produto) }}
                    <span
                      v-if="emPromocao(produto)"
                      class="text-label-small text-n-slate-10 line-through ltr:ml-1 rtl:mr-1"
                    >
                      {{ precoCheio(produto) }}
                    </span>
                  </span>
                  <span
                    v-if="produto.sku && !isFieldHidden('sku')"
                    class="text-label-small text-n-slate-10"
                  >
                    {{ produto.sku }}
                  </span>
                </div>
              </button>
            </div>
          </div>

          <footer
            class="flex items-center justify-between gap-3 px-5 py-4 border-t border-n-slate-3 dark:border-n-slate-7"
          >
            <p
              v-if="isWaha && podeEnviar"
              class="text-label-small text-n-amber-11 m-0 flex items-start gap-1.5"
            >
              <span class="i-lucide-info size-3.5 shrink-0 mt-0.5" />
              {{ avisoWaha }}
            </p>
            <span v-else class="text-label-small text-n-slate-11">
              {{
                t('CONVERSATION.CATALOG.SELECTED', {
                  count: selecionados.length,
                })
              }}
            </span>
            <div class="flex items-center gap-2 shrink-0">
              <button
                type="button"
                class="reset-base h-9 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                @click="fechar"
              >
                {{ t('CONVERSATION.CATALOG.CANCEL') }}
              </button>
              <button
                type="button"
                class="reset-base h-9 px-4 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
                :disabled="!podeEnviar"
                @click="enviar"
              >
                {{ t('CONVERSATION.CATALOG.SEND') }}
              </button>
            </div>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
