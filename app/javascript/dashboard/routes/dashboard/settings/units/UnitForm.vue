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
import NextSelect from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  dataLegivel,
  dataDaEnesimaOcorrencia,
  proximasOcorrencias,
} from './unitSchedule';

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

const CATEGORIAS = ['feriado', 'evento', 'manutencao', 'temporada'];
const FREQUENCIAS = ['nao_repete', 'semanal', 'mensal', 'anual'];
const POSICOES = [1, 2, 3, 4, -1]; // -1 = última do mês
const DIAS_DA_SEMANA = [0, 1, 2, 3, 4, 5, 6];

const COR_DA_CATEGORIA = {
  feriado: 'bg-n-ruby-3 text-n-ruby-11',
  evento: 'bg-n-blue-3 text-n-blue-11',
  manutencao: 'bg-n-amber-3 text-n-amber-11',
  temporada: 'bg-n-teal-3 text-n-teal-11',
};

const REGRA_VAZIA = {
  name: '',
  category: 'feriado',
  closed_all_day: true,
  from: '08:00',
  to: '12:00',
  starts_on: '',
  temPeriodo: false,
  ends_on: '',
  frequency: 'nao_repete',
  repeat_interval: 1,
  weekdays: [],
  mensalPor: 'posicao',
  month_day: 1,
  week_positions: [],
  termino: 'nunca',
  until_date: '',
  ocorrencias: 12,
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
const rules = ref([]);
const novaRegra = ref({ ...REGRA_VAZIA });

const rascunhoLimpo = () => ({
  ...REGRA_VAZIA,
  weekdays: [],
  week_positions: [],
});

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
  rules.value = (u?.exceptions ?? []).map(regra => ({ ...regra }));
  novaRegra.value = rascunhoLimpo();
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

// --- regras de agenda --------------------------------------------------------------

const categorias = computed(() =>
  CATEGORIAS.map(valor => ({
    value: valor,
    label: t(`UNITS_MGMT.FORM.RULES.CATEGORY.${valor.toUpperCase()}`),
  }))
);

const frequencias = computed(() =>
  FREQUENCIAS.map(valor => ({
    value: valor,
    label: t(`UNITS_MGMT.FORM.RULES.REPEAT.${valor.toUpperCase()}`),
  }))
);

const emHoraEMinuto = valor => valor.split(':').map(Number);

const alternar = (lista, valor) => {
  const i = lista.indexOf(valor);
  if (i > -1) lista.splice(i, 1);
  else lista.push(valor);
};

const usaPosicaoNoMes = rascunho =>
  rascunho.frequency === 'mensal' && rascunho.mensalPor === 'posicao';

// O rascunho da tela vira a regra que a API entende — e é a mesma conversão que
// alimenta a prévia, para o que se vê ser exatamente o que se grava.
const comoRegra = rascunho => {
  const [openHour, openMinutes] = emHoraEMinuto(rascunho.from);
  const [closeHour, closeMinutes] = emHoraEMinuto(rascunho.to);
  const porPosicao = usaPosicaoNoMes(rascunho);
  const fechada = rascunho.closed_all_day;

  const regra = {
    name: rascunho.name.trim(),
    category: rascunho.category,
    closed_all_day: fechada,
    starts_on: rascunho.starts_on,
    ends_on:
      rascunho.frequency === 'nao_repete' && rascunho.temPeriodo
        ? rascunho.ends_on || null
        : null,
    frequency: rascunho.frequency,
    repeat_interval: Number(rascunho.repeat_interval) || 1,
    weekdays:
      rascunho.frequency === 'semanal' || porPosicao
        ? [...rascunho.weekdays].sort((a, b) => a - b)
        : [],
    week_positions: porPosicao
      ? [...rascunho.week_positions].sort((a, b) => a - b)
      : [],
    month_days:
      rascunho.frequency === 'mensal' && rascunho.mensalPor === 'dia_do_mes'
        ? [Number(rascunho.month_day)]
        : [],
    until_date: null,
    open_hour: fechada ? null : openHour,
    open_minutes: fechada ? null : openMinutes,
    close_hour: fechada ? null : closeHour,
    close_minutes: fechada ? null : closeMinutes,
  };

  // "Termina após N ocorrências" não existe no banco: vira a data-limite equivalente.
  if (rascunho.frequency !== 'nao_repete') {
    if (rascunho.termino === 'data')
      regra.until_date = rascunho.until_date || null;
    if (rascunho.termino === 'contagem') {
      regra.until_date =
        dataDaEnesimaOcorrencia(regra, Number(rascunho.ocorrencias) || 1) ||
        null;
    }
  }

  return regra;
};

// "Falta escolher" não é o mesmo que "está errado": o que ainda não foi preenchido
// aparece como dica em cinza; vermelho fica para o que se contradiz.
const faltando = computed(() => {
  const rascunho = novaRegra.value;
  const chave = 'UNITS_MGMT.FORM.RULES.ERRORS';

  if (rascunho.frequency === 'semanal' && !rascunho.weekdays.length) {
    return t(`${chave}.WEEKDAY_REQUIRED`);
  }
  if (
    usaPosicaoNoMes(rascunho) &&
    (!rascunho.weekdays.length || !rascunho.week_positions.length)
  ) {
    return t(`${chave}.MONTHLY_REQUIRED`);
  }
  return '';
});

const erroDaRegra = computed(() => {
  const rascunho = novaRegra.value;
  const chave = 'UNITS_MGMT.FORM.RULES.ERRORS';

  if (!rascunho.closed_all_day && rascunho.from >= rascunho.to) {
    return t(`${chave}.INVALID_RANGE`);
  }
  if (
    rascunho.temPeriodo &&
    rascunho.ends_on &&
    rascunho.ends_on < rascunho.starts_on
  ) {
    return t(`${chave}.END_BEFORE_START`);
  }
  if (
    rascunho.termino === 'data' &&
    rascunho.until_date &&
    rascunho.until_date < rascunho.starts_on
  ) {
    return t(`${chave}.END_BEFORE_START`);
  }
  return '';
});

const podeAdicionar = computed(
  () =>
    !!novaRegra.value.name.trim() &&
    !!novaRegra.value.starts_on &&
    !faltando.value &&
    !erroDaRegra.value
);

const previa = computed(() => {
  if (!podeAdicionar.value) return [];
  return proximasOcorrencias(comoRegra(novaRegra.value), 4).map(data =>
    data.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
  );
});

const nomeDoDia = dia => t(`UNITS_MGMT.WEEKDAYS_SHORT.${dia}`);

// Frase humana da recorrência — é o que a lista mostra no lugar de uma data solta.
const resumoDaRegra = regra => {
  const chave = 'UNITS_MGMT.FORM.RULES.SUMMARY';
  const dias = regra.weekdays.map(nomeDoDia).join(', ');
  const posicoes = regra.week_positions
    .map(posicao => t(`UNITS_MGMT.FORM.RULES.POSITIONS.${posicao}`))
    .join(', ');
  let frase;

  if (regra.frequency === 'semanal') {
    frase =
      regra.repeat_interval > 1
        ? t(`${chave}.WEEKLY_EVERY`, { n: regra.repeat_interval, dias })
        : t(`${chave}.WEEKLY`, { dias });
  } else if (regra.frequency === 'mensal') {
    if (regra.month_days.length) {
      frase = regra.month_days.includes(-1)
        ? t(`${chave}.MONTHLY_LAST_DAY`)
        : t(`${chave}.MONTHLY_DAY`, { dia: regra.month_days[0] });
    } else {
      frase = t(`${chave}.MONTHLY_POSITION`, { posicoes, dias });
    }
  } else if (regra.frequency === 'anual') {
    frase = t(`${chave}.YEARLY`, { data: dataLegivel(regra.starts_on) });
  } else if (regra.ends_on) {
    frase = t(`${chave}.PERIOD`, {
      inicio: dataLegivel(regra.starts_on),
      fim: dataLegivel(regra.ends_on),
    });
  } else {
    frase = dataLegivel(regra.starts_on);
  }

  if (regra.until_date) {
    frase += ` · ${t(`${chave}.UNTIL`, { data: dataLegivel(regra.until_date) })}`;
  }
  return frase;
};

const faixaDaRegra = regra =>
  regra.closed_all_day
    ? t('UNITS_MGMT.FORM.RULES.EFFECT.CLOSED')
    : `${String(regra.open_hour).padStart(2, '0')}:${String(regra.open_minutes).padStart(2, '0')} – ${String(regra.close_hour).padStart(2, '0')}:${String(regra.close_minutes).padStart(2, '0')}`;

const adicionarRegra = () => {
  if (!podeAdicionar.value) return;
  rules.value.push(comoRegra(novaRegra.value));
  novaRegra.value = rascunhoLimpo();
};

// O backend substitui o conjunto inteiro, então remover é tirar da lista: o que
// sobra é o que fica gravado.
const removerRegra = index => {
  rules.value.splice(index, 1);
};

const regrasVisiveis = computed(() =>
  rules.value
    .map((regra, index) => ({
      ...regra,
      index,
      resumo: resumoDaRegra(regra),
      faixa: faixaDaRegra(regra),
      cor: COR_DA_CATEGORIA[regra.category] || COR_DA_CATEGORIA.feriado,
      rotulo: t(
        `UNITS_MGMT.FORM.RULES.CATEGORY.${regra.category.toUpperCase()}`
      ),
    }))
    .sort((a, b) => a.starts_on.localeCompare(b.starts_on))
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
    exceptions: rules.value,
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
        v-if="regrasVisiveis.length"
        class="p-0 mx-0 mt-0 mb-3 list-none border rounded-lg divide-y divide-n-weak border-n-weak"
      >
        <li
          v-for="regra in regrasVisiveis"
          :key="regra.index"
          class="flex flex-wrap items-center gap-3 px-3 py-2"
        >
          <span
            class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
            :class="regra.cor"
          >
            {{ regra.rotulo }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">{{
            regra.name
          }}</span>
          <span class="flex-1 min-w-32 text-n-slate-11 text-label-small">
            {{ regra.resumo }}
          </span>
          <span
            class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
            :class="
              regra.closed_all_day
                ? 'bg-n-slate-3 text-n-slate-11'
                : 'bg-n-blue-3 text-n-blue-11'
            "
          >
            {{ regra.faixa }}
          </span>
          <Button
            ghost
            slate
            xs
            icon="i-lucide-trash-2"
            @click.prevent="removerRegra(regra.index)"
          />
        </li>
      </ul>

      <div
        class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-wrap items-end gap-3">
          <div class="flex flex-col gap-1">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.CATEGORY.LABEL') }}
            </span>
            <NextSelect v-model="novaRegra.category" :options="categorias" />
          </div>
          <woot-input
            v-model="novaRegra.name"
            class="flex-1 mb-0 min-w-48"
            :label="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME')"
            :placeholder="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME_PLACEHOLDER')"
          />
        </div>

        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <label class="flex items-center gap-2 mb-0 cursor-pointer">
            <input
              v-model="novaRegra.closed_all_day"
              type="radio"
              class="m-0"
              :value="true"
            />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.RULES.EFFECT.CLOSED') }}
            </span>
          </label>
          <label class="flex items-center gap-2 mb-0 cursor-pointer">
            <input
              v-model="novaRegra.closed_all_day"
              type="radio"
              class="m-0"
              :value="false"
            />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.RULES.EFFECT.SPECIAL') }}
            </span>
          </label>
          <div v-if="!novaRegra.closed_all_day" class="flex items-center gap-2">
            <input
              v-model="novaRegra.from"
              type="time"
              class="reset-base px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
            />
            <span class="text-n-slate-11">–</span>
            <input
              v-model="novaRegra.to"
              type="time"
              class="reset-base px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
            />
          </div>
        </div>

        <div class="flex flex-wrap items-end gap-3">
          <woot-input
            v-model="novaRegra.starts_on"
            type="date"
            class="mb-0 w-44"
            :label="t('UNITS_MGMT.FORM.RULES.STARTS_ON')"
          />
          <div class="flex flex-col gap-1">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.REPEAT.LABEL') }}
            </span>
            <NextSelect v-model="novaRegra.frequency" :options="frequencias" />
          </div>
          <label
            v-if="novaRegra.frequency === 'nao_repete'"
            class="flex items-center h-10 gap-2 mb-0 cursor-pointer"
          >
            <input v-model="novaRegra.temPeriodo" type="checkbox" class="m-0" />
            <span class="text-sm text-n-slate-12">
              {{ t('UNITS_MGMT.FORM.RULES.PERIOD') }}
            </span>
          </label>
          <woot-input
            v-if="novaRegra.frequency === 'nao_repete' && novaRegra.temPeriodo"
            v-model="novaRegra.ends_on"
            type="date"
            class="mb-0 w-44"
            :label="t('UNITS_MGMT.FORM.RULES.ENDS_ON')"
          />
        </div>

        <div
          v-if="novaRegra.frequency !== 'nao_repete'"
          class="flex flex-col gap-3 p-3 rounded-lg bg-n-slate-2 dark:bg-n-solid-2"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm text-n-slate-11">
              {{ t('UNITS_MGMT.FORM.RULES.REPEAT.EVERY') }}
            </span>
            <input
              v-model="novaRegra.repeat_interval"
              type="number"
              min="1"
              max="52"
              class="reset-base w-16 px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
            />
            <span class="text-sm text-n-slate-11">
              {{
                t(
                  `UNITS_MGMT.FORM.RULES.REPEAT.UNIT_${novaRegra.frequency.toUpperCase()}`
                )
              }}
            </span>
          </div>

          <div
            v-if="novaRegra.frequency === 'mensal'"
            class="flex flex-wrap items-center gap-x-4 gap-y-2"
          >
            <label class="flex items-center gap-2 mb-0 cursor-pointer">
              <input
                v-model="novaRegra.mensalPor"
                type="radio"
                class="m-0"
                value="posicao"
              />
              <span class="text-sm text-n-slate-12">
                {{ t('UNITS_MGMT.FORM.RULES.MONTHLY.BY_POSITION') }}
              </span>
            </label>
            <label class="flex items-center gap-2 mb-0 cursor-pointer">
              <input
                v-model="novaRegra.mensalPor"
                type="radio"
                class="m-0"
                value="dia_do_mes"
              />
              <span class="text-sm text-n-slate-12">
                {{ t('UNITS_MGMT.FORM.RULES.MONTHLY.BY_DAY') }}
              </span>
            </label>
            <div
              v-if="novaRegra.mensalPor === 'dia_do_mes'"
              class="flex items-center gap-2"
            >
              <span class="text-sm text-n-slate-11">
                {{ t('UNITS_MGMT.FORM.RULES.MONTHLY.DAY') }}
              </span>
              <input
                v-model="novaRegra.month_day"
                type="number"
                min="1"
                max="31"
                class="reset-base w-16 px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
              />
            </div>
          </div>

          <div
            v-if="
              novaRegra.frequency === 'mensal' &&
              novaRegra.mensalPor === 'posicao'
            "
            class="flex flex-wrap items-center gap-1.5"
          >
            <button
              v-for="posicao in POSICOES"
              :key="posicao"
              type="button"
              class="px-2.5 py-1 text-sm rounded-lg outline outline-1 transition-colors"
              :class="
                novaRegra.week_positions.includes(posicao)
                  ? 'bg-n-brand text-white outline-transparent'
                  : 'outline-n-weak text-n-slate-12 hover:outline-n-slate-6'
              "
              @click="alternar(novaRegra.week_positions, posicao)"
            >
              {{ t(`UNITS_MGMT.FORM.RULES.POSITIONS.${posicao}`) }}
            </button>
          </div>

          <div
            v-if="
              novaRegra.frequency === 'semanal' ||
              (novaRegra.frequency === 'mensal' &&
                novaRegra.mensalPor === 'posicao')
            "
            class="flex flex-wrap items-center gap-1.5"
          >
            <button
              v-for="dia in DIAS_DA_SEMANA"
              :key="dia"
              type="button"
              class="px-2.5 py-1 text-sm rounded-lg outline outline-1 transition-colors"
              :class="
                novaRegra.weekdays.includes(dia)
                  ? 'bg-n-brand text-white outline-transparent'
                  : 'outline-n-weak text-n-slate-12 hover:outline-n-slate-6'
              "
              @click="alternar(novaRegra.weekdays, dia)"
            >
              {{ t(`UNITS_MGMT.WEEKDAYS_SHORT.${dia}`) }}
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
            <span class="text-sm text-n-slate-11">
              {{ t('UNITS_MGMT.FORM.RULES.END.LABEL') }}
            </span>
            <label class="flex items-center gap-2 mb-0 cursor-pointer">
              <input
                v-model="novaRegra.termino"
                type="radio"
                class="m-0"
                value="nunca"
              />
              <span class="text-sm text-n-slate-12">
                {{ t('UNITS_MGMT.FORM.RULES.END.NEVER') }}
              </span>
            </label>
            <label class="flex items-center gap-2 mb-0 cursor-pointer">
              <input
                v-model="novaRegra.termino"
                type="radio"
                class="m-0"
                value="data"
              />
              <span class="text-sm text-n-slate-12">
                {{ t('UNITS_MGMT.FORM.RULES.END.ON') }}
              </span>
            </label>
            <input
              v-if="novaRegra.termino === 'data'"
              v-model="novaRegra.until_date"
              type="date"
              class="reset-base px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
            />
            <label class="flex items-center gap-2 mb-0 cursor-pointer">
              <input
                v-model="novaRegra.termino"
                type="radio"
                class="m-0"
                value="contagem"
              />
              <span class="text-sm text-n-slate-12">
                {{ t('UNITS_MGMT.FORM.RULES.END.AFTER') }}
              </span>
            </label>
            <div
              v-if="novaRegra.termino === 'contagem'"
              class="flex items-center gap-2"
            >
              <input
                v-model="novaRegra.ocorrencias"
                type="number"
                min="1"
                max="365"
                class="reset-base w-16 px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12"
              />
              <span class="text-sm text-n-slate-11">
                {{ t('UNITS_MGMT.FORM.RULES.END.OCCURRENCES') }}
              </span>
            </div>
          </div>
        </div>

        <div
          class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-n-weak"
        >
          <span class="text-n-slate-11 text-label-small">
            <template v-if="previa.length">
              {{ t('UNITS_MGMT.FORM.RULES.PREVIEW') }}: {{ previa.join(' · ') }}
            </template>
            <template v-else-if="faltando">
              {{ faltando }}
            </template>
            <template v-else-if="podeAdicionar">
              {{ t('UNITS_MGMT.FORM.RULES.PREVIEW_EMPTY') }}
            </template>
          </span>
          <Button
            :label="t('UNITS_MGMT.FORM.RULES.ADD')"
            sm
            :disabled="!podeAdicionar"
            @click.prevent="adicionarRegra"
          />
        </div>

        <p v-if="erroDaRegra" class="m-0 text-n-ruby-9 text-label-small">
          {{ erroDaRegra }}
        </p>
      </div>

      <p class="mt-2 mb-0 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.RULES.PRECEDENCE') }}
      </p>
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
