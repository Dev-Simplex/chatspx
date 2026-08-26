<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import UnitForm from './UnitForm.vue';

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();

const units = useMapGetter('units/getUnits');
const uiFlags = useMapGetter('units/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const searchQuery = ref('');
const selectedUnit = ref(null);
const [showFormPopup, toggleFormPopup] = useToggle(false);
const [showDeletePopup, toggleDeletePopup] = useToggle(false);

onMounted(() => {
  store.dispatch('units/get');
  if (!inboxes.value.length) store.dispatch('inboxes/get');
});

const DIAS_CURTOS = [0, 1, 2, 3, 4, 5, 6];

// Resumo de uma linha para a lista: quantos dias abrem e quais fecham. A grade
// completa fica no modal — a lista precisa dar o panorama, não o detalhe.
const resumoDaGrade = unit => {
  const grade = unit.working_hours || [];
  const abertos = DIAS_CURTOS.filter(
    dia => !grade.find(h => h.day_of_week === dia)?.closed_all_day
  );
  if (!abertos.length) return t('UNITS_MGMT.LIST.ALL_CLOSED');
  return abertos.map(dia => t(`UNITS_MGMT.WEEKDAYS_SHORT.${dia}`)).join(', ');
};

const nomesDasCaixas = unit =>
  (unit.inbox_ids || [])
    .map(id => inboxes.value.find(i => i.id === id)?.name)
    .filter(Boolean);

const derivadas = computed(() =>
  units.value.map(unit => ({
    ...unit,
    local: [unit.city, unit.state].filter(Boolean).join('/') || '—',
    resumo: resumoDaGrade(unit),
    caixas: nomesDasCaixas(unit),
  }))
);

const filtradas = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return derivadas.value;
  return picoSearch(derivadas.value, query, [
    'name',
    'city',
    'state',
    'address',
  ]);
});

const cabecalhos = computed(() => [
  t('UNITS_MGMT.LIST.HEADERS.NAME'),
  t('UNITS_MGMT.LIST.HEADERS.LOCATION'),
  t('UNITS_MGMT.LIST.HEADERS.INBOXES'),
  t('UNITS_MGMT.LIST.HEADERS.OPEN_DAYS'),
  '',
]);

const abrirCriacao = () => {
  selectedUnit.value = null;
  toggleFormPopup(true);
};

const abrirEdicao = unit => {
  selectedUnit.value = unit;
  toggleFormPopup(true);
};

const fecharForm = () => {
  toggleFormPopup(false);
  selectedUnit.value = null;
};

const salvar = async payload => {
  try {
    if (selectedUnit.value) {
      await store.dispatch('units/update', {
        id: selectedUnit.value.id,
        ...payload,
      });
      useAlert(t('UNITS_MGMT.EDIT.API.SUCCESS'));
    } else {
      await store.dispatch('units/create', payload);
      useAlert(t('UNITS_MGMT.ADD.API.SUCCESS'));
    }
    fecharForm();
  } catch (error) {
    useAlert(error?.message || t('UNITS_MGMT.ADD.API.ERROR'));
  }
};

const confirmarExclusao = unit => {
  selectedUnit.value = unit;
  toggleDeletePopup(true);
};

const fecharExclusao = () => {
  toggleDeletePopup(false);
  selectedUnit.value = null;
};

const excluir = async () => {
  try {
    await store.dispatch('units/delete', selectedUnit.value.id);
    useAlert(t('UNITS_MGMT.DELETE.API.SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('UNITS_MGMT.DELETE.API.ERROR'));
  } finally {
    fecharExclusao();
  }
};

const isSaving = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('UNITS_MGMT.LOADING')"
    :no-records-found="!units.length"
    :no-records-message="$t('UNITS_MGMT.LIST.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('UNITS_MGMT.HEADER')"
        :description="$t('UNITS_MGMT.DESCRIPTION')"
        :search-placeholder="$t('UNITS_MGMT.SEARCH_PLACEHOLDER')"
      >
        <template v-if="units.length" #count>
          <span class="text-body-main text-n-slate-11 truncate min-w-0">
            {{ $t('UNITS_MGMT.COUNT', { n: units.length }) }}
          </span>
        </template>
        <template v-if="isAdmin" #actions>
          <Button
            :label="$t('UNITS_MGMT.ADD.BUTTON')"
            size="sm"
            @click="abrirCriacao"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="cabecalhos"
        :items="filtradas"
        :no-data-message="$t('UNITS_MGMT.LIST.NO_RESULTS')"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="unit in items" :key="unit.id">
            <BaseTableCell>
              <span class="font-medium text-n-slate-12">{{ unit.name }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-n-slate-11">{{ unit.local }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-n-slate-11">
                {{
                  unit.caixas.length
                    ? unit.caixas.join(', ')
                    : $t('UNITS_MGMT.LIST.NO_INBOX')
                }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-n-slate-11">{{ unit.resumo }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <div v-if="isAdmin" class="flex gap-2 justify-end">
                <Button
                  v-tooltip.top="$t('UNITS_MGMT.EDIT.BUTTON')"
                  icon="i-woot-edit-pen"
                  slate
                  xs
                  faded
                  @click="abrirEdicao(unit)"
                />
                <Button
                  v-tooltip.top="$t('UNITS_MGMT.DELETE.BUTTON')"
                  icon="i-lucide-trash-2"
                  ruby
                  xs
                  faded
                  @click="confirmarExclusao(unit)"
                />
              </div>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-modal
      v-model:show="showFormPopup"
      :on-close="fecharForm"
      size="medium"
    >
      <div class="flex flex-col h-auto overflow-auto">
        <woot-modal-header
          :header-title="
            selectedUnit
              ? `${$t('UNITS_MGMT.EDIT.TITLE')} - ${selectedUnit.name}`
              : $t('UNITS_MGMT.ADD.TITLE')
          "
        />
        <UnitForm
          :unit="selectedUnit"
          :is-saving="isSaving"
          @submit="salvar"
          @cancel="fecharForm"
        />
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="fecharExclusao"
      :on-confirm="excluir"
      :title="$t('UNITS_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('UNITS_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="selectedUnit?.name || ''"
      :confirm-text="$t('UNITS_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="$t('UNITS_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
