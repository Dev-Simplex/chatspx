<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCatalogLabels } from 'dashboard/composables/useCatalogLabels';
import { CatalogCategories, CatalogProducts } from 'dashboard/api/catalog';
import CatalogLayout from './CatalogLayout.vue';
import CatalogCustomFieldInput from './CatalogCustomFieldInput.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { formatarPreco, paraCampoDeReais, paraCentavos } from './catalogoPreco';
import CatalogMetaBadge from './CatalogMetaBadge.vue';

// A Meta busca a foto e faz cache dela; o que ela exibe é um quadrado de 800px. Recusar aqui o
// arquivo que ela recusaria depois evita o "a foto não aparece" descoberto só no envio.
const TIPOS_ACEITOS = ['image/jpeg', 'image/png'];
const TAMANHO_MAXIMO = 2 * 1024 * 1024;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { labels, isFieldHidden } = useCatalogLabels();

// Campos personalizados: um conjunto só por conta, na ordem em que foram criados.
const porModelo = useMapGetter('attributes/getAttributesByModel');
const definicoes = computed(() =>
  [...porModelo.value('catalog_attribute')].sort((a, b) => a.id - b.id)
);
// O que o servidor devolveu (número, texto, booleano) e, por cima, o que o usuário mexeu nesta
// tela. Separados de propósito: formatar a cada tecla reescrevia o campo de moeda enquanto a
// pessoa digitava ("2500" virava "2,00500").
const camposSalvos = ref({});
const camposEditados = ref({});

// `new` é o id que a grade manda para criar. Ele decide POST contra PATCH e se a tela abre
// buscando o produto ou em branco.
const ehNovo = computed(() => route.params.productId === 'new');
const produtoId = computed(() => route.params.productId);

const nome = ref('');
const descricao = ref('');
const preco = ref('');
const precoPromocional = ref('');
const sku = ref('');
const estoque = ref('');
const categoriaId = ref('');
const visivel = ref(true);
const destaque = ref(false);
const moeda = ref('BRL');

const fotos = ref([]);
const novasFotos = ref([]);
const categorias = ref([]);

// O painel de sincronização mostra o produto COMO O BACKEND O DEVOLVEU (`meta_status` é calculado
// lá). Por isso ele guarda a última resposta, e não os campos que o usuário está editando.
const produtoSalvo = ref(null);
const metaSyncEnabled = ref(false);
const sincronizando = ref(false);

const carregando = ref(false);
const salvando = ref(false);
const erro = ref('');
const erroDoNome = ref('');
const erroDaFoto = ref('');

const arquivoRef = ref(null);

const aplicar = produto => {
  nome.value = produto.name || '';
  descricao.value = produto.description || '';
  preco.value = paraCampoDeReais(produto.price_cents);
  precoPromocional.value = paraCampoDeReais(produto.promo_price_cents);
  sku.value = produto.sku || '';
  estoque.value =
    produto.stock === null || produto.stock === undefined
      ? ''
      : String(produto.stock);
  categoriaId.value = produto.catalog_category_id
    ? String(produto.catalog_category_id)
    : '';
  visivel.value = Boolean(produto.visible);
  destaque.value = Boolean(produto.featured);
  moeda.value = produto.currency || 'BRL';
  fotos.value = produto.images || [];
  camposSalvos.value = produto.custom_attributes || {};
  camposEditados.value = {};
  produtoSalvo.value = produto;
  metaSyncEnabled.value = Boolean(produto.meta_sync_enabled);
};

const carregarProduto = async () => {
  carregando.value = true;
  try {
    const { data } = await CatalogProducts.show(produtoId.value);
    aplicar(data);
  } catch {
    erro.value = t('CATALOG_MGMT.FORM.LOAD_ERROR');
  } finally {
    carregando.value = false;
  }
};

const carregarCategorias = async () => {
  try {
    const { data } = await CatalogCategories.get();
    categorias.value = data || [];
  } catch {
    // Sem categorias o produto ainda se cadastra: categoria é opcional no banco.
    categorias.value = [];
  }
};

onMounted(() => {
  carregarCategorias();
  store.dispatch('attributes/get');
  if (!ehNovo.value) carregarProduto();
});

// As prévias são URLs de objeto do navegador; sem revogar, cada foto escolhida e descartada fica
// segurando o arquivo em memória enquanto a aba viver.
onBeforeUnmount(() => {
  novasFotos.value.forEach(foto => URL.revokeObjectURL(foto.previa));
});

const opcoesDeCategoria = computed(() => [
  { value: '', label: t('CATALOG_MGMT.FORM.FIELDS.NO_CATEGORY') },
  ...categorias.value.map(categoria => ({
    value: String(categoria.id),
    label: categoria.name,
  })),
]);

const titulo = computed(() =>
  nome.value.trim()
    ? nome.value.trim()
    : t('CATALOG_MGMT.FORM.NEW_TITLE', labels.value)
);

// Conta sem espelho, ou produto ainda não criado, não tem o que sincronizar.
const mostrarSincronizacao = computed(
  () => metaSyncEnabled.value && Boolean(produtoSalvo.value)
);

// Incompleto nunca vai: a passada o pularia. Oculto não tem estado, e sai da Meta sozinho.
const podeSincronizar = computed(() =>
  ['sincronizado', 'pendente'].includes(produtoSalvo.value?.meta_status)
);

// A resposta traz o produto PENDENTE: o job é assíncrono, e fingir que sincronizou mentiria.
const sincronizarAgora = async () => {
  sincronizando.value = true;
  try {
    const { data } = await CatalogProducts.sincronizarProduto(produtoId.value);
    produtoSalvo.value = data;
    useAlert(t('CATALOG_MGMT.FORM.SYNC.QUEUED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CATALOG_MGMT.FORM.SYNC.ERROR'));
  } finally {
    sincronizando.value = false;
  }
};

// A prévia mostra o preço que o cliente veria hoje: a promoção vence o cheio, a mesma regra que o
// `preco_atual_cents` do backend aplica na lista.
const precoCentavos = computed(() => paraCentavos(preco.value));
const promoCentavos = computed(() => paraCentavos(precoPromocional.value));

const emPromocao = computed(
  () =>
    promoCentavos.value !== null &&
    precoCentavos.value !== null &&
    promoCentavos.value < precoCentavos.value
);

// Sem preço a prévia não mostra preço (`formatarPreco` devolve vazio para nulo).
const precoDaPrevia = computed(() =>
  formatarPreco(
    emPromocao.value ? promoCentavos.value : precoCentavos.value,
    moeda.value
  )
);

const precoCheioDaPrevia = computed(() =>
  emPromocao.value ? formatarPreco(precoCentavos.value, moeda.value) : ''
);

const capaDaPrevia = computed(() => {
  if (fotos.value.length) return fotos.value[0].url;

  return novasFotos.value.length ? novasFotos.value[0].previa : '';
});

const escolherArquivo = () => arquivoRef.value?.click();

const receberArquivos = evento => {
  erroDaFoto.value = '';

  Array.from(evento.target.files || []).forEach(arquivo => {
    if (!TIPOS_ACEITOS.includes(arquivo.type)) {
      erroDaFoto.value = t('CATALOG_MGMT.FORM.PHOTOS.INVALID_TYPE', {
        name: arquivo.name,
      });
      return;
    }

    if (arquivo.size > TAMANHO_MAXIMO) {
      erroDaFoto.value = t('CATALOG_MGMT.FORM.PHOTOS.TOO_BIG', {
        name: arquivo.name,
      });
      return;
    }

    novasFotos.value.push({ arquivo, previa: URL.createObjectURL(arquivo) });
  });

  // Zerar o input deixa escolher o MESMO arquivo de novo depois de removê-lo; sem isso o
  // `change` não dispara na segunda vez.
  evento.target.value = '';
};

const removerNova = indice => {
  URL.revokeObjectURL(novasFotos.value[indice].previa);
  novasFotos.value.splice(indice, 1);
};

// Foto já salva sai pelo endpoint de imagem: o update acrescenta imagens, nunca substitui a lista.
const removerSalva = async imagem => {
  try {
    const { data } = await CatalogProducts.removerImagem(
      produtoId.value,
      imagem.id
    );
    fotos.value = data.images || [];
  } catch {
    erroDaFoto.value = t('CATALOG_MGMT.FORM.PHOTOS.REMOVE_ERROR');
  }
};

// O valor de moeda volta do servidor como número (2500.5); o campo edita em reais com vírgula.
const valorSalvo = definicao => {
  const valor = camposSalvos.value[definicao.attribute_key];
  if (definicao.attribute_display_type === 'checkbox') return valor === true;
  if (valor === undefined || valor === null) return '';
  if (definicao.attribute_display_type === 'currency')
    return Number(valor).toFixed(2).replace('.', ',');

  return String(valor);
};

const valorDoCampo = definicao =>
  definicao.attribute_key in camposEditados.value
    ? camposEditados.value[definicao.attribute_key]
    : valorSalvo(definicao);

const mudarCampo = (definicao, valor) => {
  camposEditados.value = {
    ...camposEditados.value,
    [definicao.attribute_key]: valor,
  };
};

// FormData e não JSON porque as fotos viajam no mesmo salvar. Campo vazio vai como string vazia,
// que o Rails converte para NULL em coluna numérica — é o que apaga uma promoção ou um preço.
const montarCorpo = () => {
  const corpo = new FormData();

  corpo.append('catalog_product[name]', nome.value.trim());
  corpo.append('catalog_product[description]', descricao.value);
  corpo.append('catalog_product[price_cents]', precoCentavos.value ?? '');
  corpo.append(
    'catalog_product[promo_price_cents]',
    promoCentavos.value === null ? '' : promoCentavos.value
  );
  corpo.append('catalog_product[currency]', moeda.value);
  corpo.append('catalog_product[sku]', sku.value.trim());
  corpo.append('catalog_product[stock]', estoque.value);
  corpo.append('catalog_product[catalog_category_id]', categoriaId.value);
  corpo.append('catalog_product[visible]', visivel.value);
  corpo.append('catalog_product[featured]', destaque.value);

  // Vão TODAS as chaves, inclusive as vazias: o servidor substitui o conjunto, e é a chave em
  // branco que apaga o valor de um campo.
  definicoes.value.forEach(definicao => {
    corpo.append(
      `catalog_product[custom_attributes][${definicao.attribute_key}]`,
      valorDoCampo(definicao)
    );
  });

  novasFotos.value.forEach(foto => {
    corpo.append('catalog_product[images][]', foto.arquivo);
  });

  return corpo;
};

const voltar = () =>
  router.push({
    name: 'catalog_products_index',
    params: { accountId: route.params.accountId },
  });

const salvar = async () => {
  erro.value = '';
  erroDoNome.value = '';

  if (!nome.value.trim()) {
    erroDoNome.value = t('CATALOG_MGMT.FORM.FIELDS.NAME_REQUIRED');
    return;
  }

  salvando.value = true;
  try {
    const corpo = montarCorpo();
    if (ehNovo.value) {
      await CatalogProducts.create(corpo);
    } else {
      await CatalogProducts.update(produtoId.value, corpo);
    }
    voltar();
  } catch (e) {
    // A mensagem da API vem das validações do model (SKU repetido, por exemplo). Ela substitui o
    // texto genérico, e o formulário fica como está para ninguém redigitar o cadastro inteiro.
    erro.value =
      e?.response?.data?.message || t('CATALOG_MGMT.FORM.SAVE_ERROR');
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <CatalogLayout
    hide-tabs
    :title="titulo"
    :back-button-label="$t('CATALOG_MGMT.FORM.BACK')"
    :is-loading="carregando"
    :loading-message="$t('CATALOG_MGMT.FORM.LOADING')"
  >
    <template #count>
      <span
        data-testid="selo-estado"
        class="px-2 py-1 rounded-md text-label-small"
        :class="
          visivel
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-slate-4 text-n-slate-11'
        "
      >
        {{
          visivel
            ? $t('CATALOG_MGMT.FORM.STATE.ACTIVE')
            : $t('CATALOG_MGMT.FORM.STATE.HIDDEN')
        }}
      </span>
    </template>
    <template #actions>
      <Button
        data-testid="salvar-produto"
        :label="$t('CATALOG_MGMT.FORM.SAVE')"
        :is-loading="salvando"
        size="sm"
        @click="salvar"
      />
    </template>

    <template #preBody>
      <div
        v-if="erro"
        data-testid="erro-do-formulario"
        class="flex items-center gap-2 px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-11"
      >
        <span class="i-lucide-triangle-alert size-4" />
        {{ erro }}
      </div>
    </template>

    <template #body>
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div class="flex flex-col gap-5 lg:col-span-2">
          <div class="flex flex-col gap-2">
            <span class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.PHOTOS.LABEL') }}
            </span>
            <div class="flex flex-wrap gap-3">
              <div
                v-for="foto in fotos"
                :key="foto.id"
                class="relative overflow-hidden border rounded-lg size-24 border-n-weak bg-n-slate-3 dark:bg-n-solid-3"
              >
                <img
                  :src="foto.url"
                  :alt="foto.filename || nome"
                  class="object-cover w-full h-full"
                />
                <button
                  type="button"
                  data-testid="remover-foto"
                  :aria-label="$t('CATALOG_MGMT.FORM.PHOTOS.REMOVE')"
                  class="absolute grid rounded-full top-1 ltr:right-1 rtl:left-1 size-5 place-items-center bg-n-solid-1 text-n-slate-11 dark:bg-n-solid-2"
                  @click="removerSalva(foto)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </div>
              <div
                v-for="(foto, indice) in novasFotos"
                :key="foto.previa"
                class="relative overflow-hidden border rounded-lg size-24 border-n-weak bg-n-slate-3 dark:bg-n-solid-3"
              >
                <img
                  :src="foto.previa"
                  :alt="foto.arquivo.name"
                  class="object-cover w-full h-full"
                />
                <button
                  type="button"
                  data-testid="remover-foto-nova"
                  :aria-label="$t('CATALOG_MGMT.FORM.PHOTOS.REMOVE')"
                  class="absolute grid rounded-full top-1 ltr:right-1 rtl:left-1 size-5 place-items-center bg-n-solid-1 text-n-slate-11 dark:bg-n-solid-2"
                  @click="removerNova(indice)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </div>
              <button
                type="button"
                data-testid="adicionar-foto"
                :aria-label="$t('CATALOG_MGMT.FORM.PHOTOS.ADD')"
                class="grid transition-shadow border border-dashed rounded-lg size-24 place-items-center border-n-weak text-n-slate-11 hover:shadow-md"
                @click="escolherArquivo"
              >
                <span class="i-lucide-plus size-5" />
              </button>
              <input
                ref="arquivoRef"
                type="file"
                class="hidden"
                accept="image/jpeg,image/png"
                multiple
                data-testid="campo-de-foto"
                @change="receberArquivos"
              />
            </div>
            <p class="text-n-slate-11 text-label-small">
              {{ $t('CATALOG_MGMT.FORM.PHOTOS.HINT') }}
            </p>
            <p
              v-if="erroDaFoto"
              data-testid="erro-da-foto"
              class="text-n-ruby-11 text-label-small"
            >
              {{ erroDaFoto }}
            </p>
          </div>

          <Input
            v-model="nome"
            data-testid="campo-nome"
            :label="$t('CATALOG_MGMT.FORM.FIELDS.NAME')"
            :message="erroDoNome"
            :message-type="erroDoNome ? 'error' : 'info'"
          />

          <TextArea
            v-model="descricao"
            data-testid="campo-descricao"
            :label="$t('CATALOG_MGMT.FORM.FIELDS.DESCRIPTION')"
            :max-length="1000"
            auto-height
          />

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Input
              v-model="preco"
              data-testid="campo-preco"
              :label="$t('CATALOG_MGMT.FORM.FIELDS.PRICE')"
              :placeholder="$t('CATALOG_MGMT.FORM.FIELDS.PRICE_PLACEHOLDER')"
              :message="$t('CATALOG_MGMT.FORM.FIELDS.PRICE_HINT')"
            />
            <Input
              v-if="!isFieldHidden('promo_price')"
              v-model="precoPromocional"
              data-testid="campo-preco-promocional"
              :label="$t('CATALOG_MGMT.FORM.FIELDS.PROMO_PRICE')"
              :placeholder="$t('CATALOG_MGMT.FORM.FIELDS.PRICE_PLACEHOLDER')"
            />
          </div>

          <div
            v-if="!isFieldHidden('sku') || !isFieldHidden('stock')"
            class="grid grid-cols-1 gap-4 sm:grid-cols-2"
          >
            <Input
              v-if="!isFieldHidden('sku')"
              v-model="sku"
              data-testid="campo-sku"
              :label="$t('CATALOG_MGMT.FORM.FIELDS.SKU')"
            />
            <Input
              v-if="!isFieldHidden('stock')"
              v-model="estoque"
              data-testid="campo-estoque"
              type="number"
              min="0"
              :label="$t('CATALOG_MGMT.FORM.FIELDS.STOCK')"
            />
          </div>

          <div class="flex flex-col gap-2">
            <span class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.FIELDS.CATEGORY') }}
            </span>
            <Select
              v-model="categoriaId"
              data-testid="campo-categoria"
              :options="opcoesDeCategoria"
            />
          </div>

          <div
            v-if="definicoes.length"
            data-testid="secao-campos"
            class="flex flex-col gap-4 pt-5 border-t border-n-weak"
          >
            <h3 class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.CUSTOM_FIELDS.TITLE') }}
            </h3>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <CatalogCustomFieldInput
                v-for="definicao in definicoes"
                :key="definicao.id"
                :definicao="definicao"
                :model-value="valorDoCampo(definicao)"
                @update:model-value="mudarCampo(definicao, $event)"
              />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-6">
          <div
            class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
          >
            <h3 class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.PUBLISH.TITLE') }}
            </h3>
            <!-- O mockup traz um terceiro interruptor, "Espelhar na Meta". Ele não existe no
                 banco: o espelho da C9 leva todo produto visível, então ligá-lo aqui seria um
                 botão que não muda nada. Volta quando houver coluna. -->
            <div class="flex items-start gap-3">
              <Switch v-model="visivel" data-testid="interruptor-visivel" />
              <div class="flex flex-col">
                <span class="font-medium text-n-slate-12 text-body-main">
                  {{ $t('CATALOG_MGMT.FORM.PUBLISH.VISIBLE') }}
                </span>
                <span class="text-n-slate-11 text-label-small">
                  {{ $t('CATALOG_MGMT.FORM.PUBLISH.VISIBLE_HINT') }}
                </span>
              </div>
            </div>
            <div
              v-if="!isFieldHidden('featured')"
              class="flex items-start gap-3"
            >
              <Switch v-model="destaque" data-testid="interruptor-destaque" />
              <div class="flex flex-col">
                <span class="font-medium text-n-slate-12 text-body-main">
                  {{ $t('CATALOG_MGMT.FORM.PUBLISH.FEATURED') }}
                </span>
                <span class="text-n-slate-11 text-label-small">
                  {{ $t('CATALOG_MGMT.FORM.PUBLISH.FEATURED_HINT') }}
                </span>
              </div>
            </div>
          </div>

          <div
            v-if="mostrarSincronizacao"
            data-testid="painel-sincronizacao"
            class="flex flex-col items-start gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
          >
            <h3 class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.SYNC.TITLE') }}
            </h3>
            <CatalogMetaBadge
              v-if="produtoSalvo.meta_status"
              :produto="produtoSalvo"
            />
            <span v-else class="text-n-slate-11 text-label-small">
              {{ $t('CATALOG_MGMT.FORM.SYNC.HIDDEN') }}
            </span>
            <span
              v-if="produtoSalvo.meta_product_id"
              class="text-n-slate-11 text-label-small"
            >
              {{
                $t('CATALOG_MGMT.FORM.SYNC.PRODUCT_ID', {
                  id: produtoSalvo.meta_product_id,
                })
              }}
            </span>
            <Button
              v-if="podeSincronizar"
              data-testid="sincronizar-produto"
              :label="$t('CATALOG_MGMT.FORM.SYNC.NOW')"
              :is-loading="sincronizando"
              icon="i-lucide-refresh-cw"
              size="sm"
              variant="faded"
              color="slate"
              @click="sincronizarAgora"
            />
          </div>

          <div class="flex flex-col gap-3">
            <h3 class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FORM.PREVIEW.TITLE') }}
            </h3>
            <!-- Prévia estática: desenha o cartão como ele chega no WhatsApp e não manda nada. -->
            <div
              data-testid="previa-do-cliente"
              class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
            >
              <div
                class="grid w-full place-items-center aspect-square bg-n-slate-3 dark:bg-n-solid-3"
              >
                <img
                  v-if="capaDaPrevia"
                  :src="capaDaPrevia"
                  :alt="titulo"
                  class="object-cover w-full h-full"
                />
                <span v-else class="i-lucide-image size-10 text-n-slate-10" />
              </div>
              <div class="flex flex-col gap-1 p-3">
                <span class="font-medium text-n-slate-12 text-body-main">
                  {{ titulo }}
                </span>
                <span
                  v-if="precoDaPrevia"
                  class="flex flex-wrap items-baseline gap-1.5"
                >
                  <span class="font-semibold text-n-teal-11">
                    {{ precoDaPrevia }}
                  </span>
                  <span
                    v-if="precoCheioDaPrevia"
                    class="line-through text-n-slate-10 text-label-small"
                  >
                    {{ precoCheioDaPrevia }}
                  </span>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </CatalogLayout>
</template>
