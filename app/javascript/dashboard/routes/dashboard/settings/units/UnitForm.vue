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
import Button from 'dashboard/components-next/button/Button.vue';

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
const novaExcecao = ref({ date: '', name: '', closed_all_day: true });

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
};
carregar();
watch(() => props.unit, carregar);

const nomeInvalido = computed(() => !form.value.name.trim());
const timezones = timeZoneOptions();

const onSlotUpdate = slot => {
  const i = timeSlots.value.findIndex(s => s.day === slot.day);
  if (i > -1) timeSlots.value[i] = slot;
};

const adicionarExcecao = () => {
  const { date, name } = novaExcecao.value;
  if (!date || !name.trim()) return;
  exceptions.value.push({ ...novaExcecao.value });
  novaExcecao.value = { date: '', name: '', closed_all_day: true };
};

// O backend substitui o conjunto inteiro, então remover é tirar da lista: o que
// sobra é o que fica gravado.
const removerExcecao = index => {
  exceptions.value.splice(index, 1);
};

const excecoesVisiveis = computed(() =>
  exceptions.value.map((e, index) => ({ ...e, index }))
);

const onSubmit = () => {
  if (nomeInvalido.value) return;
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
  <form class="flex flex-col gap-6" @submit.prevent="onSubmit">
    <div class="grid gap-4 sm:grid-cols-2">
      <woot-input
        v-model="form.name"
        :label="t('UNITS_MGMT.FORM.NAME.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.NAME.PLACEHOLDER')"
        :class="{ error: nomeInvalido }"
      />
      <woot-input
        v-model="form.phone"
        :label="t('UNITS_MGMT.FORM.PHONE.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.PHONE.PLACEHOLDER')"
      />
      <woot-input
        v-model="form.city"
        :label="t('UNITS_MGMT.FORM.CITY.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.CITY.PLACEHOLDER')"
      />
      <woot-input
        v-model="form.state"
        :label="t('UNITS_MGMT.FORM.STATE.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.STATE.PLACEHOLDER')"
      />
    </div>
    <woot-input
      v-model="form.address"
      :label="t('UNITS_MGMT.FORM.ADDRESS.LABEL')"
      :placeholder="t('UNITS_MGMT.FORM.ADDRESS.PLACEHOLDER')"
    />

    <label>
      {{ t('UNITS_MGMT.FORM.TIMEZONE.LABEL') }}
      <select v-model="form.timezone">
        <option v-for="tz in timezones" :key="tz.value" :value="tz.value">
          {{ tz.label }}
        </option>
      </select>
    </label>

    <div>
      <label class="block mb-1">{{ t('UNITS_MGMT.FORM.INBOXES.LABEL') }}</label>
      <p class="mt-0 mb-2 text-n-slate-11 text-label-small">
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
    </div>

    <div>
      <label class="block mb-1">{{ t('UNITS_MGMT.FORM.HOURS.LABEL') }}</label>
      <p class="mt-0 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.HOURS.HELP') }}
      </p>
      <BusinessDay
        v-for="slot in timeSlots"
        :key="slot.day"
        :day-name="t(`UNITS_MGMT.WEEKDAYS.${slot.day}`)"
        :day-index="slot.day"
        :from-time="slot.from"
        :to-time="slot.to"
        :is-open-all-day="slot.openAllDay"
        :is-enabled="slot.valid"
        @update="onSlotUpdate"
      />
    </div>

    <div>
      <label class="block mb-1">{{
        t('UNITS_MGMT.FORM.EXCEPTIONS.LABEL')
      }}</label>
      <p class="mt-0 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.EXCEPTIONS.HELP') }}
      </p>
      <ul
        v-if="excecoesVisiveis.length"
        class="mb-3 divide-y border rounded-lg border-n-weak"
      >
        <li
          v-for="excecao in excecoesVisiveis"
          :key="excecao.index"
          class="flex items-center gap-3 px-3 py-2"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            excecao.date
          }}</span>
          <span class="flex-1 text-sm truncate text-n-slate-11">{{
            excecao.name
          }}</span>
          <span class="etiqueta text-label-small text-n-slate-11">
            {{
              excecao.closed_all_day
                ? t('UNITS_MGMT.FORM.EXCEPTIONS.CLOSED')
                : t('UNITS_MGMT.FORM.EXCEPTIONS.SPECIAL_HOURS')
            }}
          </span>
          <span
            v-if="excecao.annual"
            class="etiqueta text-label-small text-n-slate-11"
          >
            {{ t('UNITS_MGMT.FORM.EXCEPTIONS.ANNUAL') }}
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
      <div class="flex flex-wrap items-end gap-2">
        <woot-input
          v-model="novaExcecao.date"
          type="date"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.EXCEPTIONS.DATE')"
        />
        <woot-input
          v-model="novaExcecao.name"
          class="flex-1 mb-0"
          :label="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME')"
          :placeholder="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME_PLACEHOLDER')"
        />
        <Button
          faded
          slate
          :label="t('UNITS_MGMT.FORM.EXCEPTIONS.ADD')"
          @click.prevent="adicionarExcecao"
        />
      </div>
    </div>

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
        :disabled="nomeInvalido || isSaving"
      />
    </div>
  </form>
</template>
