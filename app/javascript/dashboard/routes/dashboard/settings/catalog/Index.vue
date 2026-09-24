<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { CatalogCategories, CatalogProducts } from 'dashboard/api/catalog';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CatalogProductCard from './CatalogProductCard.vue';

// Quem digita busca o produto no meio do atendimento: esperar o dedo parar evita uma consulta por
// tecla, e 300ms é o intervalo que as outras buscas da casa já usam.
const ESPERA_DA_BUSCA = 300;
const POR_PAGINA_PADRAO = 25;

const { t } = useI18n();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();

const busca = ref('');
const categoriaId = ref('');
const soVisiveis = ref(false);
const pagina = ref(1);

const produtos = ref([]);
const categorias = ref([]);
const total = ref(0);
const porPagina = ref(POR_PAGINA_PADRAO);
const carregando = ref(true);
const erro = ref('');

const carregar = async () => {
  carregando.value = true;
  erro.value = '';
  try {
    const { data } = await CatalogProducts.listar({
      page: pagina.value,
      q: busca.value.trim(),
      categoryId: categoriaId.value,
      visibleOnly: soVisiveis.value,
    });
    produtos.value = data.payload || [];
    total.value = data.meta?.total || 0;
    porPagina.value = data.meta?.per_page || POR_PAGINA_PADRAO;
  } catch {
    erro.value = t('CATALOG_MGMT.LIST.ERROR');
    produtos.value = [];
    total.value = 0;
  } finally {
    carregando.value = false;
  }
};

// Mexer em qualquer filtro volta para a primeira página: manter a página 4 depois de filtrar
// mostraria uma lista vazia de um resultado que tem só uma página.
const recomecar = () => {
  pagina.value = 1;
  carregar();
};

const irParaPagina = numero => {
  pagina.value = numero;
  carregar();
};

// Os filtros conversam com a API, não com a lista em memória: peneirar no cliente esconderia o
// que está nas outras páginas.
const buscarComEspera = useDebounceFn(recomecar, ESPERA_DA_BUSCA);
watch(busca, buscarComEspera);
watch([categoriaId, soVisiveis], recomecar);

const carregarCategorias = async () => {
  try {
    const { data } = await CatalogCategories.get();
    categorias.value = data || [];
  } catch {
    // Sem categorias o filtro some, mas a vitrine continua de pé — não é motivo para alarmar.
    categorias.value = [];
  }
};

onMounted(() => {
  carregar();
  carregarCategorias();
});

const opcoesDeCategoria = computed(() => [
  { value: '', label: t('CATALOG_MGMT.FILTERS.ALL_CATEGORIES') },
  ...categorias.value.map(categoria => ({
    value: String(categoria.id),
    label: categoria.name,
  })),
]);

const semRegistros = computed(
  () => !carregando.value && !erro.value && !produtos.value.length
);

// O cadastro é só de administrador (rota e `CatalogProductPolicy`): o atendente navega pela grade,
// mas abrir o formulário para ele seria mostrar uma tela que o salvar recusa.
const abrirCadastro = (produto = null) => {
  if (!isAdmin.value) return;

  router.push({
    name: 'catalog_product_edit',
    params: {
      accountId: route.params.accountId,
      productId: produto ? produto.id : 'new',
    },
  });
};
</script>

<template>
  <SettingsLayout
    :is-loading="carregando"
    :loading-message="$t('CATALOG_MGMT.LOADING')"
    :no-records-found="semRegistros"
    :no-records-message="$t('CATALOG_MGMT.LIST.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="busca"
        :title="$t('CATALOG_MGMT.HEADER')"
        :description="$t('CATALOG_MGMT.DESCRIPTION')"
        :search-placeholder="$t('CATALOG_MGMT.SEARCH_PLACEHOLDER')"
      >
        <template #count>
          <span class="min-w-0 truncate text-body-main text-n-slate-11">
            {{ $t('CATALOG_MGMT.COUNT', { n: total }) }}
          </span>
        </template>
        <template #actions>
          <Button
            v-if="isAdmin"
            :label="$t('CATALOG_MGMT.ADD.BUTTON')"
            size="sm"
            @click="abrirCadastro()"
          />
        </template>
      </BaseSettingsHeader>
      <div class="flex flex-wrap items-center gap-3 mt-4">
        <Select
          v-model="categoriaId"
          data-testid="filtro-categoria"
          :options="opcoesDeCategoria"
        />
        <label
          class="flex items-center gap-2 cursor-pointer text-n-slate-11 text-body-main"
        >
          <Checkbox v-model="soVisiveis" />
          {{ $t('CATALOG_MGMT.FILTERS.VISIBLE_ONLY') }}
        </label>
      </div>
    </template>

    <template #preBody>
      <div
        v-if="erro"
        data-testid="catalogo-erro"
        class="flex items-center gap-2 px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-11"
      >
        <span class="i-lucide-triangle-alert size-4" />
        {{ erro }}
      </div>
    </template>

    <template #body>
      <div
        data-testid="catalogo-grade"
        class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4"
      >
        <CatalogProductCard
          v-for="produto in produtos"
          :key="produto.id"
          :produto="produto"
          @abrir="abrirCadastro"
        />
      </div>
      <PaginationFooter
        v-if="total > porPagina"
        class="mt-4"
        :current-page="pagina"
        :total-items="total"
        :items-per-page="porPagina"
        @update:current-page="irParaPagina"
      />
    </template>
  </SettingsLayout>
</template>
