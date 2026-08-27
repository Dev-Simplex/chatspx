<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
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
import { timeZoneOptions } from '../inbox/helpers/businessHour.js';
import { situacaoDaUnidade } from './unitSchedule';

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();

const units = useMapGetter('units/getUnits');
const uiFlags = useMapGetter('units/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

const searchQuery = ref('');
// Relógio da tela: a situação da unidade vira sozinha quando dá a hora de fechar, e
// sem o tique a lista continuaria dizendo "aberta" até alguém recarregar a página.
const agora = ref(new Date());
let cronometro = null;
const selectedUnit = ref(null);
const [showFormPopup, toggleFormPopup] = useToggle(false);
const [showDeletePopup, toggleDeletePopup] = useToggle(false);

onMounted(() => {
  store.dispatch('units/get');
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  cronometro = setInterval(() => {
    agora.value = new Date();
  }, 60000);
});

onBeforeUnmount(() => clearInterval(cronometro));

const ROTULO_DO_FUSO = Object.fromEntries(
  timeZoneOptions().map(fuso => [fuso.value, fuso.label])
);

// Mesma paleta do editor de regras: a etiqueta diz de que natureza é o dia de hoje.
const COR_DA_CATEGORIA = {
  feriado: 'bg-n-ruby-3 text-n-ruby-11',
  evento: 'bg-n-blue-3 text-n-blue-11',
  manutencao: 'bg-n-amber-3 text-n-amber-11',
  temporada: 'bg-n-teal-3 text-n-teal-11',
};

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

// Uma linha só: o feriado do dia (quando há) e a faixa que vale hoje.
const resumoDeHoje = situacao => {
  const partes = [situacao.excecao, situacao.faixa].filter(Boolean);
  return partes.length ? partes.join(' · ') : t('UNITS_MGMT.LIST.CLOSED_TODAY');
};

const nomesDasCaixas = unit =>
  (unit.inbox_ids || [])
    .map(id => inboxes.value.find(i => i.id === id)?.name)
    .filter(Boolean);

const derivadas = computed(() =>
  units.value.map(unit => {
    const situacao = situacaoDaUnidade(unit, agora.value);
    return {
      ...unit,
      local: [unit.city, unit.state].filter(Boolean).join('/') || '—',
      fuso: ROTULO_DO_FUSO[unit.timezone] || unit.timezone,
      resumo: resumoDaGrade(unit),
      caixas: nomesDasCaixas(unit),
      situacao,
      hoje: resumoDeHoje(situacao),
    };
  })
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
  t('UNITS_MGMT.LIST.HEADERS.STATUS'),
  t('UNITS_MGMT.LIST.HEADERS.OPEN_DAYS'),
  t('UNITS_MGMT.LIST.HEADERS.INBOXES'),
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
              <div class="flex flex-col">
                <span class="font-medium text-n-slate-12">{{ unit.name }}</span>
                <span
                  v-if="unit.address || unit.phone"
                  class="truncate text-n-slate-11 text-label-small max-w-64"
                >
                  {{ [unit.address, unit.phone].filter(Boolean).join(' · ') }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex flex-col">
                <span class="text-n-slate-11">{{ unit.local }}</span>
                <span class="text-n-slate-11 text-label-small">
                  {{ unit.fuso }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex flex-col gap-1 items-start">
                <div class="flex items-center gap-1.5">
                  <span
                    class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
                    :class="
                      unit.situacao.aberta
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-slate-3 text-n-slate-11'
                    "
                  >
                    {{
                      unit.situacao.aberta
                        ? $t('UNITS_MGMT.LIST.OPEN_NOW')
                        : $t('UNITS_MGMT.LIST.CLOSED_NOW')
                    }}
                  </span>
                  <span
                    v-if="unit.situacao.categoria"
                    class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
                    :class="COR_DA_CATEGORIA[unit.situacao.categoria]"
                  >
                    {{
                      $t(
                        `UNITS_MGMT.FORM.RULES.CATEGORY.${unit.situacao.categoria.toUpperCase()}`
                      )
                    }}
                  </span>
                </div>
                <span
                  class="whitespace-nowrap text-n-slate-11 text-label-small"
                >
                  {{ unit.hoje }}
                </span>
                <span
                  class="whitespace-nowrap text-n-slate-10 text-label-small"
                >
                  {{
                    $t('UNITS_MGMT.LIST.LOCAL_TIME', {
                      time: unit.situacao.horaLocal,
                    })
                  }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-n-slate-11">{{ unit.resumo }}</span>
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
