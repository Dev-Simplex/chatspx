<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCatalogLabels } from 'dashboard/composables/useCatalogLabels';
import { CatalogCategories } from 'dashboard/api/catalog';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CatalogLayout from './CatalogLayout.vue';

const { t } = useI18n();
const { item, items } = useCatalogLabels();

const categorias = ref([]);
const carregando = ref(true);
const erro = ref('');

// `null` = criando; com categoria = renomeando. O mesmo diálogo serve aos dois.
const emEdicao = ref(null);
const nome = ref('');
const erroDoNome = ref('');
const salvando = ref(false);
const apagando = ref(null);
const dialogoDoNome = ref(null);
const dialogoDeApagar = ref(null);

const carregar = async () => {
  erro.value = '';
  try {
    const { data } = await CatalogCategories.get();
    categorias.value = data || [];
  } catch {
    erro.value = t('CATALOG_MGMT.CATEGORIES.API.LOAD_ERROR');
  } finally {
    carregando.value = false;
  }
};

onMounted(carregar);

const vazio = computed(
  () => !carregando.value && !erro.value && !categorias.value.length
);

const quantos = n =>
  t('CATALOG_MGMT.CATEGORIES.COUNT', {
    n,
    items: n === 1 ? item.value : items.value,
  });

const abrirNome = (categoria = null) => {
  emEdicao.value = categoria;
  nome.value = categoria?.name || '';
  erroDoNome.value = '';
  dialogoDoNome.value.open();
};

const salvarNome = async () => {
  if (!nome.value.trim()) return;

  salvando.value = true;
  erroDoNome.value = '';
  const corpo = { catalog_category: { name: nome.value.trim() } };
  try {
    if (emEdicao.value) {
      await CatalogCategories.update(emEdicao.value.id, corpo);
    } else {
      await CatalogCategories.create(corpo);
    }
    dialogoDoNome.value.close();
    useAlert(t('CATALOG_MGMT.CATEGORIES.API.SAVED'));
    await carregar();
  } catch (e) {
    // Nome repetido: o servidor diz qual é o problema, e o diálogo fica aberto para corrigir.
    erroDoNome.value =
      e?.response?.data?.message || t('CATALOG_MGMT.CATEGORIES.API.SAVE_ERROR');
  } finally {
    salvando.value = false;
  }
};

const pedirParaApagar = categoria => {
  apagando.value = categoria;
  dialogoDeApagar.value.open();
};

const avisoDeApagar = computed(() => {
  const n = apagando.value?.products_count || 0;
  if (!n) return t('CATALOG_MGMT.CATEGORIES.DELETE_DIALOG.DESCRIPTION_EMPTY');

  return t('CATALOG_MGMT.CATEGORIES.DELETE_DIALOG.DESCRIPTION', {
    n,
    items: n === 1 ? item.value : items.value,
  });
});

const apagar = async () => {
  salvando.value = true;
  try {
    await CatalogCategories.delete(apagando.value.id);
    dialogoDeApagar.value.close();
    useAlert(t('CATALOG_MGMT.CATEGORIES.API.DELETED'));
    await carregar();
  } catch {
    useAlert(t('CATALOG_MGMT.CATEGORIES.API.DELETE_ERROR'));
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <CatalogLayout
    :description="$t('CATALOG_MGMT.CATEGORIES.DESCRIPTION')"
    :is-loading="carregando"
    :loading-message="$t('CATALOG_MGMT.CATEGORIES.LOADING')"
  >
    <template #actions>
      <Button
        v-if="!vazio"
        data-testid="nova-categoria"
        :label="$t('CATALOG_MGMT.CATEGORIES.ADD')"
        icon="i-lucide-plus"
        size="sm"
        @click="abrirNome()"
      />
    </template>

    <template #body>
      <div
        v-if="erro"
        data-testid="categorias-erro"
        class="flex items-center gap-2 px-4 py-3 rounded-lg bg-n-ruby-3 text-n-ruby-11"
      >
        <span class="i-lucide-triangle-alert size-4" />
        {{ erro }}
      </div>

      <div
        v-else-if="vazio"
        data-testid="categorias-vazio"
        class="flex flex-col items-center gap-3 px-4 py-16 text-center border border-dashed rounded-xl border-n-weak"
      >
        <span class="i-lucide-folder-tree size-8 text-n-slate-10" />
        <span class="font-medium text-n-slate-12 text-body-main">
          {{ $t('CATALOG_MGMT.CATEGORIES.EMPTY.TITLE') }}
        </span>
        <span class="text-n-slate-11 text-body-main">
          {{ $t('CATALOG_MGMT.CATEGORIES.EMPTY.HINT') }}
        </span>
        <Button
          data-testid="primeira-categoria"
          :label="$t('CATALOG_MGMT.CATEGORIES.EMPTY.BUTTON')"
          size="sm"
          @click="abrirNome()"
        />
      </div>

      <ul
        v-else
        data-testid="categorias-lista"
        class="flex flex-col p-0 m-0 list-none border divide-y rounded-xl border-n-weak divide-n-weak bg-n-solid-1 dark:bg-n-solid-2"
      >
        <li
          v-for="categoria in categorias"
          :key="categoria.id"
          class="flex items-center gap-3 px-4 py-3"
        >
          <span class="i-lucide-folder size-4 text-n-slate-10 shrink-0" />
          <span
            class="flex-1 min-w-0 font-medium truncate text-n-slate-12 text-body-main"
          >
            {{ categoria.name }}
          </span>
          <span class="text-n-slate-11 text-label-small shrink-0">
            {{ quantos(categoria.products_count || 0) }}
          </span>
          <Button
            v-tooltip.top="$t('CATALOG_MGMT.CATEGORIES.RENAME')"
            data-testid="renomear-categoria"
            icon="i-lucide-pencil"
            size="sm"
            variant="ghost"
            color="slate"
            :aria-label="$t('CATALOG_MGMT.CATEGORIES.RENAME')"
            @click="abrirNome(categoria)"
          />
          <Button
            v-tooltip.top="$t('CATALOG_MGMT.CATEGORIES.DELETE')"
            data-testid="apagar-categoria"
            icon="i-lucide-trash-2"
            size="sm"
            variant="ghost"
            color="ruby"
            :aria-label="$t('CATALOG_MGMT.CATEGORIES.DELETE')"
            @click="pedirParaApagar(categoria)"
          />
        </li>
      </ul>

      <Dialog
        ref="dialogoDoNome"
        :title="
          emEdicao
            ? $t('CATALOG_MGMT.CATEGORIES.DIALOG.RENAME_TITLE')
            : $t('CATALOG_MGMT.CATEGORIES.DIALOG.CREATE_TITLE')
        "
        :confirm-button-label="$t('CATALOG_MGMT.CATEGORIES.DIALOG.SAVE')"
        :cancel-button-label="$t('CATALOG_MGMT.CATEGORIES.DIALOG.CANCEL')"
        :disable-confirm-button="!nome.trim()"
        :is-loading="salvando"
        @confirm="salvarNome"
      >
        <Input
          v-model="nome"
          data-testid="nome-da-categoria"
          :label="$t('CATALOG_MGMT.CATEGORIES.DIALOG.NAME')"
          :placeholder="$t('CATALOG_MGMT.CATEGORIES.DIALOG.NAME_PLACEHOLDER')"
          :message="erroDoNome"
          :message-type="erroDoNome ? 'error' : 'info'"
        />
      </Dialog>

      <Dialog
        ref="dialogoDeApagar"
        type="alert"
        :title="
          $t('CATALOG_MGMT.CATEGORIES.DELETE_DIALOG.TITLE', {
            name: apagando?.name,
          })
        "
        :description="avisoDeApagar"
        :confirm-button-label="
          $t('CATALOG_MGMT.CATEGORIES.DELETE_DIALOG.CONFIRM')
        "
        :cancel-button-label="
          $t('CATALOG_MGMT.CATEGORIES.DELETE_DIALOG.CANCEL')
        "
        :is-loading="salvando"
        @confirm="apagar"
      />
    </template>
  </CatalogLayout>
</template>
