import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

// Cada conta escolhe como chamar o item do catálogo (Produto, Imóvel, Serviço) e quais campos
// padrão esconder. Tudo vem de `currentAccount.settings`; vazio cai no texto padrão.
//
// `labels` vai direto como parâmetro do i18n: t('CATALOG_MGMT.ADD.BUTTON', labels.value). Os nomes
// entram em minúscula porque sempre caem no meio de frase ("Adicionar imóvel", "12 imóveis").
export function useCatalogLabels() {
  const { t } = useI18n();
  const { currentAccount } = useAccount();

  const settings = computed(() => currentAccount.value?.settings || {});

  const nome = (chave, padrao) =>
    (settings.value[chave] || '').trim().toLocaleLowerCase() || t(padrao);

  const item = computed(() =>
    nome('catalog_item_singular', 'CATALOG_MGMT.ITEM.SINGULAR')
  );
  const items = computed(() =>
    nome('catalog_item_plural', 'CATALOG_MGMT.ITEM.PLURAL')
  );
  const labels = computed(() => ({ item: item.value, items: items.value }));

  const hiddenFields = computed(
    () => settings.value.catalog_hidden_fields || []
  );
  const isFieldHidden = campo => hiddenFields.value.includes(campo);

  return { item, items, labels, hiddenFields, isFieldHidden };
}
