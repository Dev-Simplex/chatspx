<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import AddAttribute from 'dashboard/routes/dashboard/settings/attributes/AddAttribute.vue';
import EditAttribute from 'dashboard/routes/dashboard/settings/attributes/EditAttribute.vue';
import CatalogLayout from './CatalogLayout.vue';

// Campos padrão que a conta pode esconder. A chave é a que vai em `catalog_hidden_fields`.
const ESCONDIVEIS = [
  { chave: 'sku', rotulo: 'CATALOG_MGMT.FIELDS_TAB.STANDARD.SKU' },
  { chave: 'stock', rotulo: 'CATALOG_MGMT.FIELDS_TAB.STANDARD.STOCK' },
  { chave: 'featured', rotulo: 'CATALOG_MGMT.FIELDS_TAB.STANDARD.FEATURED' },
  {
    chave: 'promo_price',
    rotulo: 'CATALOG_MGMT.FIELDS_TAB.STANDARD.PROMO_PRICE',
  },
];
const TAMANHO_DO_NOME = 30;

const { t } = useI18n();
const store = useStore();
const { currentAccount, updateAccount } = useAccount();

// ---- Campos padrão -------------------------------------------------------------------------
const singular = ref('');
const plural = ref('');
// A tela fala em "mostrar", o servidor guarda quem está ESCONDIDO: `visiveis[chave]` é o avesso.
const visiveis = ref({});
const salvando = ref(false);

const aplicar = settings => {
  singular.value = settings?.catalog_item_singular || '';
  plural.value = settings?.catalog_item_plural || '';
  const escondidos = settings?.catalog_hidden_fields || [];
  visiveis.value = Object.fromEntries(
    ESCONDIVEIS.map(({ chave }) => [chave, !escondidos.includes(chave)])
  );
};

// A conta pode ainda não estar na store quando a aba abre por link direto.
watch(() => currentAccount.value?.settings, aplicar, { immediate: true });

const salvarPadrao = async () => {
  salvando.value = true;
  try {
    await updateAccount({
      catalog_item_singular: singular.value.trim(),
      catalog_item_plural: plural.value.trim(),
      catalog_hidden_fields: ESCONDIVEIS.map(({ chave }) => chave).filter(
        chave => !visiveis.value[chave]
      ),
    });
    useAlert(t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SAVED'));
  } catch {
    useAlert(t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SAVE_ERROR'));
  } finally {
    salvando.value = false;
  }
};

// ---- Campos personalizados -----------------------------------------------------------------
const porModelo = useMapGetter('attributes/getAttributesByModel');
const uiFlags = useMapGetter('attributes/getUIFlags');
const campos = computed(() => porModelo.value('catalog_attribute'));

const criando = ref(false);
const editando = ref(false);
const selecionado = ref(null);
const dialogoDeApagar = ref(null);

onMounted(() => store.dispatch('attributes/get'));

const editar = campo => {
  selecionado.value = campo;
  editando.value = true;
};

const pedirParaApagar = campo => {
  selecionado.value = campo;
  dialogoDeApagar.value.open();
};

const apagar = async () => {
  try {
    await store.dispatch('attributes/delete', selecionado.value.id);
    dialogoDeApagar.value.close();
    useAlert(t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETED'));
  } catch {
    useAlert(t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE_ERROR'));
  }
};

const tipo = campo =>
  t(
    `ATTRIBUTES_MGMT.ATTRIBUTE_TYPES.${campo.attribute_display_type.toUpperCase()}`
  );
</script>

<template>
  <CatalogLayout>
    <template #body>
      <div class="flex flex-col gap-6">
        <section
          data-testid="campos-padrao"
          class="flex flex-col gap-5 p-4 border sm:p-5 rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
        >
          <header class="flex flex-col gap-1">
            <h2 class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.TITLE') }}
            </h2>
            <p class="m-0 text-n-slate-11 text-label-small">
              {{ $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.DESCRIPTION') }}
            </p>
          </header>

          <div class="flex flex-col gap-2">
            <span class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.NAME_TITLE') }}
            </span>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Input
                v-model="singular"
                data-testid="nome-singular"
                :maxlength="TAMANHO_DO_NOME"
                :label="$t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SINGULAR')"
                :placeholder="
                  $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SINGULAR_PLACEHOLDER')
                "
              />
              <Input
                v-model="plural"
                data-testid="nome-plural"
                :maxlength="TAMANHO_DO_NOME"
                :label="$t('CATALOG_MGMT.FIELDS_TAB.STANDARD.PLURAL')"
                :placeholder="
                  $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.PLURAL_PLACEHOLDER')
                "
              />
            </div>
          </div>

          <div class="flex flex-col gap-3">
            <span class="font-medium text-n-slate-12 text-body-main">
              {{ $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.VISIBILITY_TITLE') }}
            </span>
            <div
              v-for="campo in ESCONDIVEIS"
              :key="campo.chave"
              class="flex items-start gap-3"
            >
              <Switch
                v-model="visiveis[campo.chave]"
                :data-testid="`mostrar-${campo.chave}`"
              />
              <div class="flex flex-col">
                <span class="text-n-slate-12 text-body-main">
                  {{ $t(campo.rotulo) }}
                </span>
                <span
                  v-if="campo.chave === 'sku'"
                  class="text-n-slate-11 text-label-small"
                >
                  {{ $t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SKU_HINT') }}
                </span>
              </div>
            </div>
          </div>

          <div class="flex justify-end">
            <Button
              data-testid="salvar-campos-padrao"
              :label="$t('CATALOG_MGMT.FIELDS_TAB.STANDARD.SAVE')"
              :is-loading="salvando"
              size="sm"
              @click="salvarPadrao"
            />
          </div>
        </section>

        <section
          data-testid="campos-personalizados"
          class="flex flex-col gap-4 p-4 border sm:p-5 rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
        >
          <header class="flex flex-wrap items-start justify-between gap-3">
            <div class="flex flex-col gap-1">
              <h2 class="font-medium text-n-slate-12 text-body-main">
                {{ $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.TITLE') }}
              </h2>
              <p class="m-0 text-n-slate-11 text-label-small">
                {{ $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DESCRIPTION') }}
              </p>
            </div>
            <Button
              data-testid="novo-campo"
              :label="$t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.ADD')"
              icon="i-lucide-plus"
              size="sm"
              @click="criando = true"
            />
          </header>

          <p
            v-if="!campos.length"
            class="py-8 m-0 text-center text-n-slate-11 text-body-main"
          >
            {{ $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.EMPTY') }}
          </p>
          <ul
            v-else
            class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
          >
            <li
              v-for="campo in campos"
              :key="campo.id"
              data-testid="campo-personalizado"
              class="flex items-center gap-3 py-3"
            >
              <div class="flex flex-col flex-1 min-w-0">
                <span class="flex flex-wrap items-center gap-2">
                  <span
                    class="font-medium truncate text-n-slate-12 text-body-main"
                  >
                    {{ campo.attribute_display_name }}
                  </span>
                  <span
                    v-if="campo.hidden"
                    data-testid="selo-interno"
                    class="px-2 py-0.5 rounded-md text-label-small bg-n-slate-4 text-n-slate-11"
                  >
                    {{ $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.INTERNAL') }}
                  </span>
                </span>
                <span class="truncate text-n-slate-11 text-label-small">
                  {{ tipo(campo) }} · {{ campo.attribute_key }}
                </span>
              </div>
              <Button
                v-tooltip.top="$t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.EDIT')"
                data-testid="editar-campo"
                icon="i-lucide-pencil"
                size="sm"
                variant="ghost"
                color="slate"
                :aria-label="$t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.EDIT')"
                @click="editar(campo)"
              />
              <Button
                v-tooltip.top="$t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE')"
                data-testid="apagar-campo"
                icon="i-lucide-trash-2"
                size="sm"
                variant="ghost"
                color="ruby"
                :aria-label="$t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE')"
                @click="pedirParaApagar(campo)"
              />
            </li>
          </ul>
        </section>
      </div>

      <AddAttribute
        v-if="criando"
        v-model:show="criando"
        catalog
        :on-close="() => (criando = false)"
      />
      <woot-modal v-model:show="editando" :on-close="() => (editando = false)">
        <EditAttribute
          catalog
          :selected-attribute="selecionado"
          :is-updating="uiFlags.isUpdating"
          @on-close="editando = false"
        />
      </woot-modal>
      <Dialog
        ref="dialogoDeApagar"
        type="alert"
        :title="
          $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE_DIALOG.TITLE', {
            name: selecionado?.attribute_display_name,
          })
        "
        :description="
          $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE_DIALOG.DESCRIPTION')
        "
        :confirm-button-label="
          $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE_DIALOG.CONFIRM')
        "
        :cancel-button-label="
          $t('CATALOG_MGMT.FIELDS_TAB.CUSTOM.DELETE_DIALOG.CANCEL')
        "
        :is-loading="uiFlags.isDeleting"
        @confirm="apagar"
      />
    </template>
  </CatalogLayout>
</template>
