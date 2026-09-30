<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { CatalogProducts } from 'dashboard/api/catalog';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CatalogLayout from './CatalogLayout.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

// ---- Meta ----------------------------------------------------------------------------------
const catalogoId = ref('');
const salvando = ref(false);
const sincronizando = ref(false);

const idSalvo = computed(
  () => currentAccount.value?.settings?.meta_catalog_id || ''
);

watch(idSalvo, valor => (catalogoId.value = valor), { immediate: true });

const salvarMeta = async () => {
  salvando.value = true;
  try {
    await updateAccount({ meta_catalog_id: catalogoId.value.trim() });
    useAlert(t('CATALOG_MGMT.INTEGRATIONS.META.SAVED'));
  } catch {
    useAlert(t('CATALOG_MGMT.INTEGRATIONS.META.SAVE_ERROR'));
  } finally {
    salvando.value = false;
  }
};

// Só enfileira: o job é assíncrono, então a tela não finge que sincronizou. O 422 (conta sem
// caixa do WhatsApp oficial) vem com a explicação do servidor.
const sincronizarTudo = async () => {
  sincronizando.value = true;
  try {
    await CatalogProducts.sincronizar();
    useAlert(t('CATALOG_MGMT.SYNC_ALL.QUEUED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CATALOG_MGMT.SYNC_ALL.ERROR'));
  } finally {
    sincronizando.value = false;
  }
};
</script>

<template>
  <CatalogLayout :description="$t('CATALOG_MGMT.INTEGRATIONS.DESCRIPTION')">
    <template #body>
      <div class="flex flex-col gap-6">
        <section
          data-testid="integracao-meta"
          class="flex flex-col gap-4 p-4 border sm:p-5 rounded-xl border-n-weak bg-n-solid-1 dark:bg-n-solid-2"
        >
          <header class="flex items-start gap-3">
            <span
              class="grid rounded-lg size-9 place-items-center bg-n-alpha-2 text-n-slate-11 shrink-0"
            >
              <span class="i-lucide-infinity size-5" />
            </span>
            <div class="flex flex-col gap-1">
              <h2 class="font-medium text-n-slate-12 text-body-main">
                {{ $t('CATALOG_MGMT.INTEGRATIONS.META.TITLE') }}
              </h2>
              <p class="m-0 text-n-slate-11 text-label-small">
                {{ $t('CATALOG_MGMT.INTEGRATIONS.META.DESCRIPTION') }}
              </p>
            </div>
          </header>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <Input
              v-model="catalogoId"
              data-testid="meta-catalog-id"
              class="flex-1"
              :label="$t('CATALOG_MGMT.INTEGRATIONS.META.CATALOG_ID')"
              :placeholder="
                $t('CATALOG_MGMT.INTEGRATIONS.META.CATALOG_ID_PLACEHOLDER')
              "
            />
            <Button
              data-testid="salvar-meta"
              :label="$t('CATALOG_MGMT.INTEGRATIONS.META.SAVE')"
              :is-loading="salvando"
              :disabled="catalogoId.trim() === idSalvo"
              @click="salvarMeta"
            />
          </div>

          <div
            class="flex flex-wrap items-center justify-between gap-3 pt-4 border-t border-n-weak"
          >
            <span class="text-n-slate-11 text-label-small">
              {{
                idSalvo ? '' : $t('CATALOG_MGMT.INTEGRATIONS.META.SYNC_HINT')
              }}
            </span>
            <Button
              data-testid="sincronizar-meta"
              :label="$t('CATALOG_MGMT.SYNC_ALL.BUTTON')"
              :is-loading="sincronizando"
              :disabled="!idSalvo"
              icon="i-lucide-refresh-cw"
              variant="faded"
              color="slate"
              size="sm"
              @click="sincronizarTudo"
            />
          </div>
        </section>
      </div>
    </template>
  </CatalogLayout>
</template>
