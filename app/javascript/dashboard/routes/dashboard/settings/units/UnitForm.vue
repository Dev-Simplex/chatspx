<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  timeSlotParse,
  timeSlotTransform,
  timeZoneOptions,
} from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour.js';
import BusinessDay from 'dashboard/routes/dashboard/settings/inbox/components/BusinessDay.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { dataLegivel, faixaLegivel } from './unitSchedule';

const props = defineProps({
  // Unidade existente quando é edição; nulo quando é criação.
  unit: { type: Object, default: null },
  isSaving: { type: Boolean, default: false },
});
const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');

// A grade nasce com a semana inteira mesmo na criação: o backend cria os sete dias,
// e a tela precisa de algo para desenhar antes de existir id.
const GRADE_PADRAO = [0, 1, 2, 3, 4, 5, 6].map(dia => ({
  day_of_week: dia,
  closed_all_day: [0, 6].includes(dia),
  open_all_day: false,
  open_hour: [0, 6].includes(dia) ? null : 8,
  open_minutes: [0, 6].includes(dia) ? null : 0,
  close_hour: [0, 6].includes(dia) ? null : 18,
  close_minutes: [0, 6].includes(dia) ? null : 0,
}));

const EXCECAO_VAZIA = {
  date: '',
  name: '',
  closed_all_day: true,
  annual: false,
  from: '08:00',
  to: '12:00',
};

const form = ref({
  name: '',
  city: '',
  state: '',
  address: '',
  phone: '',
  timezone: 'America/Sao_Paulo',
  notes: '',
});
const timeSlots = ref([]);
const horaIds = ref({});
const selectedInboxIds = ref([]);
const exceptions = ref([]);
const novaExcecao = ref({ ...EXCECAO_VAZIA });

const carregar = () => {
  const u = props.unit;
  form.value = {
    name: u?.name ?? '',
    city: u?.city ?? '',
    state: u?.state ?? '',
    address: u?.address ?? '',
    phone: u?.phone ?? '',
    timezone: u?.timezone ?? 'America/Sao_Paulo',
    notes: u?.notes ?? '',
  };
  const grade = u?.working_hours?.length ? u.working_hours : GRADE_PADRAO;
  // Guarda o id de cada dia: sem ele o nested attributes cria linha nova em vez de
  // atualizar a existente, e o índice único do par (unidade, dia) recusa o salvar.
  horaIds.value = Object.fromEntries(
    grade.filter(h => h.id).map(h => [h.day_of_week, h.id])
  );
  timeSlots.value = timeSlotParse(grade);
  selectedInboxIds.value = [...(u?.inbox_ids ?? [])];
  exceptions.value = (u?.exceptions ?? []).map(e => ({ ...e }));
  novaExcecao.value = { ...EXCECAO_VAZIA };
};
carregar();
watch(() => props.unit, carregar);

const timezones = timeZoneOptions();
const nomeInvalido = computed(() => !form.value.name.trim());
// Faixa invertida (fecha antes de abrir) — o próprio BusinessDay marca o dia. Dia
// fechado nasce `valid: false` sem ser erro, então só conta quem tem hora escolhida.
const gradeInvalida = computed(() =>
  timeSlots.value.some(slot => slot.from && !slot.valid)
);

const onSlotUpdate = (dia, slot) => {
  timeSlots.value = timeSlots.value.map(item =>
    item.day === dia ? slot : item
  );
};

const dataRepetida = computed(() =>
  exceptions.value.some(e => e.date === novaExcecao.value.date)
);
const faixaDaExcecaoInvalida = computed(
  () =>
    !novaExcecao.value.closed_all_day &&
    novaExcecao.value.from >= novaExcecao.value.to
);
const erroDaExcecao = computed(() => {
  if (dataRepetida.value) return t('UNITS_MGMT.FORM.EXCEPTIONS.DUPLICATE');
  if (faixaDaExcecaoInvalida.value)
    return t('UNITS_MGMT.FORM.EXCEPTIONS.INVALID_RANGE');
  return '';
});
const podeAdicionarExcecao = computed(
  () =>
    !!novaExcecao.value.date &&
    !!novaExcecao.value.name.trim() &&
    !erroDaExcecao.value
);

const emHoraEMinuto = valor => valor.split(':').map(Number);

const adicionarExcecao = () => {
  if (!podeAdicionarExcecao.value) return;
  const {
    date,
    name,
    closed_all_day: fechada,
    annual,
    from,
    to,
  } = novaExcecao.value;
  const [openHour, openMinutes] = emHoraEMinuto(from);
  const [closeHour, closeMinutes] = emHoraEMinuto(to);
  exceptions.value.push({
    date,
    name: name.trim(),
    annual,
    closed_all_day: fechada,
    // Horário especial: substitui a grade daquele dia. Fechada não manda hora nenhuma.
    open_hour: fechada ? null : openHour,
    open_minutes: fechada ? null : openMinutes,
    close_hour: fechada ? null : closeHour,
    close_minutes: fechada ? null : closeMinutes,
  });
  novaExcecao.value = { ...EXCECAO_VAZIA };
};

// O backend substitui o conjunto inteiro, então remover é tirar da lista: o que
// sobra é o que fica gravado.
const removerExcecao = index => {
  exceptions.value.splice(index, 1);
};

const excecoesVisiveis = computed(() =>
  exceptions.value
    .map((e, index) => ({
      ...e,
      index,
      dataLegivel: dataLegivel(e.date),
      faixa: faixaLegivel(e),
    }))
    .sort((a, b) => a.date.localeCompare(b.date))
);

const onSubmit = () => {
  if (nomeInvalido.value || gradeInvalida.value) return;
  emit('submit', {
    ...form.value,
    inbox_ids: selectedInboxIds.value,
    working_hours_attributes: timeSlotTransform(timeSlots.value).map(h => ({
      ...h,
      id: horaIds.value[h.day_of_week],
    })),
    exceptions: exceptions.value,
  });
};
</script>

<template>
  <form class="flex flex-col gap-8" @submit.prevent="onSubmit">
    <section class="flex flex-col gap-4">
      <div class="grid gap-4 sm:grid-cols-2">
        <woot-input
          v-model="form.name"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.NAME.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.NAME.PLACEHOLDER')"
          :class="{ error: nomeInvalido }"
        />
        <woot-input
          v-model="form.phone"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.PHONE.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.PHONE.PLACEHOLDER')"
        />
      </div>
      <woot-input
        v-model="form.address"
        class="mb-0"
        :label="t('UNITS_MGMT.FORM.ADDRESS.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.ADDRESS.PLACEHOLDER')"
      />
      <div class="grid gap-4 sm:grid-cols-3">
        <woot-input
          v-model="form.city"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.CITY.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.CITY.PLACEHOLDER')"
        />
        <woot-input
          v-model="form.state"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.STATE.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.STATE.PLACEHOLDER')"
        />
        <div class="flex flex-col gap-1">
          <span class="text-heading-3">
            {{ t('UNITS_MGMT.FORM.TIMEZONE.LABEL') }}
          </span>
          <ComboBox
            v-model="form.timezone"
            :options="timezones"
            :placeholder="t('UNITS_MGMT.FORM.TIMEZONE.PLACEHOLDER')"
            :search-placeholder="t('UNITS_MGMT.FORM.TIMEZONE.SEARCH')"
          />
        </div>
      </div>
      <p class="m-0 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.TIMEZONE.HELP') }}
      </p>
    </section>

    <section>
      <span class="text-heading-3">{{
        t('UNITS_MGMT.FORM.INBOXES.LABEL')
      }}</span>
      <p class="mt-0.5 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.INBOXES.HELP') }}
      </p>
      <div
        v-if="inboxes.length"
        class="flex flex-col gap-2.5 p-3 overflow-y-auto border border-solid rounded-lg max-h-44 border-n-weak dark:border-n-strong"
      >
        <label
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex gap-2 items-center w-fit cursor-pointer mb-0"
        >
          <input
            v-model="selectedInboxIds"
            type="checkbox"
            :value="inbox.id"
            class="m-0"
          />
          <span class="text-sm text-n-slate-12">{{ inbox.name }}</span>
        </label>
      </div>
      <p v-else class="text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.INBOXES.EMPTY') }}
      </p>
    </section>

    <section>
      <span class="text-heading-3">{{ t('UNITS_MGMT.FORM.HOURS.LABEL') }}</span>
      <p class="mt-0.5 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.HOURS.HELP') }}
      </p>
      <table
        class="min-w-full table-auto outline outline-1 -outline-offset-1 outline-n-weak rounded-xl"
      >
        <thead>
          <tr class="border-b border-n-weak">
            <th
              class="py-3 ltr:pl-4 ltr:pr-3 rtl:pl-3 rtl:pr-4 text-start text-heading-3 text-n-slate-12"
            >
              {{ t('INBOX_MGMT.BUSINESS_HOURS.DAY.DAY') }}
            </th>
            <th
              class="py-3 ltr:pr-3 rtl:pl-3 text-start text-heading-3 text-n-slate-12"
            >
              {{ t('INBOX_MGMT.BUSINESS_HOURS.DAY.AVAILABILITY') }}
            </th>
            <th
              class="py-3 ltr:pr-3 rtl:pl-3 text-start text-heading-3 text-n-slate-12"
            >
              {{ t('INBOX_MGMT.BUSINESS_HOURS.DAY.HOURS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <BusinessDay
            v-for="slot in timeSlots"
            :key="slot.day"
            :day-name="t(`UNITS_MGMT.WEEKDAYS.${slot.day}`)"
            :time-slot="slot"
            @update="dados => onSlotUpdate(slot.day, dados)"
          />
        </tbody>
      </table>
    </section>

    <section>
      <span class="text-heading-3">{{
        t('UNITS_MGMT.FORM.EXCEPTIONS.LABEL')
      }}</span>
      <p class="mt-0.5 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.EXCEPTIONS.HELP') }}
      </p>
      <ul
        v-if="excecoesVisiveis.length"
        class="p-0 mx-0 mt-0 mb-3 list-none border rounded-lg divide-y divide-n-weak border-n-weak"
      >
        <li
          v-for="excecao in excecoesVisiveis"
          :key="excecao.index"
          class="flex items-center gap-3 px-3 py-2"
        >
          <span class="text-sm font-medium tabular-nums text-n-slate-12">
            {{ excecao.dataLegivel }}
          </span>
          <span class="flex-1 text-sm truncate text-n-slate-11">
            {{ excecao.name }}
          </span>
          <span
            v-if="excecao.annual"
            class="px-2 py-1 rounded-lg text-label-small bg-n-slate-3 text-n-slate-11"
          >
            {{ t('UNITS_MGMT.FORM.EXCEPTIONS.ANNUAL') }}
          </span>
          <span
            class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
            :class="
              excecao.closed_all_day
                ? 'bg-n-ruby-3 text-n-ruby-11'
                : 'bg-n-blue-3 text-n-blue-11'
            "
          >
            {{
              excecao.closed_all_day
                ? t('UNITS_MGMT.FORM.EXCEPTIONS.CLOSED')
                : excecao.faixa
            }}
          </span>
          <Button
            ghost
            slate
            xs
            icon="i-lucide-trash-2"
            @click.prevent="removerExcecao(excecao.index)"
          />
        </li>
      </ul>
      <div class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak">
        <div class="grid gap-3 sm:grid-cols-2">
          <woot-input
            v-model="novaExcecao.date"
            type="date"
            class="mb-0"
            :label="t('UNITS_MGMT.FORM.EXCEPTIONS.DATE')"
          />
          <woot-input
            v-model="novaExcecao.name"
            class="mb-0"
            :label="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME')"
            :placeholder="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME_PLACEHOLDER')"
          />
        </div>
        <div class="flex flex-wrap items-center gap-4">
          <label class="flex items-center gap-2 mb-0 cursor-pointer">
            <input
              v-model="novaExcecao.closed_all_day"
              type="radio"
              class="m-0"
              :value="true"
            />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.EXCEPTIONS.CLOSED') }}
            </span>
          </label>
          <label class="flex items-center gap-2 mb-0 cursor-pointer">
            <input
              v-model="novaExcecao.closed_all_day"
              type="radio"
              class="m-0"
              :value="false"
            />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.EXCEPTIONS.SPECIAL_HOURS') }}
            </span>
          </label>
          <div
            v-if="!novaExcecao.closed_all_day"
            class="flex items-center gap-2"
          >
            <input
              v-model="novaExcecao.from"
              type="time"
              class="reset-base px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-white dark:bg-n-solid-2 text-n-slate-12"
            />
            <span class="text-n-slate-11">–</span>
            <input
              v-model="novaExcecao.to"
              type="time"
              class="reset-base px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-white dark:bg-n-solid-2 text-n-slate-12"
            />
          </div>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <label class="flex items-center gap-2 mb-0 cursor-pointer">
            <input v-model="novaExcecao.annual" type="checkbox" class="m-0" />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.EXCEPTIONS.ANNUAL') }}
            </span>
            <span class="text-n-slate-11 text-label-small">
              {{ t('UNITS_MGMT.FORM.EXCEPTIONS.ANNUAL_HELP') }}
            </span>
          </label>
          <Button
            faded
            slate
            sm
            :label="t('UNITS_MGMT.FORM.EXCEPTIONS.ADD')"
            :disabled="!podeAdicionarExcecao"
            @click.prevent="adicionarExcecao"
          />
        </div>
        <p v-if="erroDaExcecao" class="m-0 text-n-ruby-9 text-label-small">
          {{ erroDaExcecao }}
        </p>
      </div>
    </section>

    <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
      <Button
        faded
        slate
        type="reset"
        :label="t('UNITS_MGMT.FORM.CANCEL')"
        @click.prevent="emit('cancel')"
      />
      <Button
        type="submit"
        :label="t('UNITS_MGMT.FORM.SUBMIT')"
        :is-loading="isSaving"
        :disabled="nomeInvalido || gradeInvalida || isSaving"
      />
    </div>
  </form>
</template>
