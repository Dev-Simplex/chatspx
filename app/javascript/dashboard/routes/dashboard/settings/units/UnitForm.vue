<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  getTime,
  timeSlotParse,
  timeSlotTransform,
  timeZoneOptions,
} from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour.js';
import BusinessDay from 'dashboard/routes/dashboard/settings/inbox/components/BusinessDay.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import NextSelect from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  comoTextoISO,
  dataLegivel,
  dataDaEnesimaOcorrencia,
  proximasOcorrencias,
} from './unitSchedule';
import UnitCalendar from './UnitCalendar.vue';
import {
  formatarCep,
  formatarTelefone,
  copiarHorarioParaDias,
} from './unitFormulario';

const props = defineProps({
  // Unidade existente quando é edição; nulo quando é criação.
  unit: { type: Object, default: null },
  isSaving: { type: Boolean, default: false },
});
const emit = defineEmits(['submit', 'cancel']);

const { t, locale } = useI18n();
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

// Todo campo do painel usa a MESMA altura e o mesmo desenho. O desalinhamento vinha
// justamente disso: `woot-input` monta rótulo e caixa com espaçamento próprio e 40px de
// altura, enquanto o seletor nativo fica em 38px — alinhados pela base, os rótulos
// saíam em linhas diferentes.
const CAMPO =
  'reset-base h-10 w-full px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12 placeholder:text-n-slate-10';
const CAMPO_ESTREITO =
  'reset-base h-10 w-20 px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12';
const SELETOR = 'w-full [&>select]:h-10 [&>select]:w-full';

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
  mensalUltimoDia: false,
  week_positions: [],
  termino: 'nunca',
  until_date: '',
  ocorrencias: 12,
  reminder_days_before: '',
};

const form = ref({
  name: '',
  zip_code: '',
  city: '',
  state: '',
  address: '',
  address_number: '',
  phone: '',
  timezone: 'America/Sao_Paulo',
  notes: '',
  applies_to_inboxes: false,
});
// UM campo, e não dois: ninguém digita latitude e longitude separadas — copia o par do Google
// Maps ("-15.601, -56.097") e cola. A quebra nos dois números acontece no envio.
const coordenadas = ref('');
const timeSlots = ref([]);
const horaIds = ref({});
const selectedInboxIds = ref([]);
const rules = ref([]);
const novaRegra = ref({ ...REGRA_VAZIA });

// -1 = criando; >= 0 = editando a regra daquela posição.
const editandoIndex = ref(-1);

// Ano que o calendário está mostrando; a lista de marcações acompanha.
const anoVisivel = ref(new Date().getFullYear());

const rascunhoLimpo = () => ({
  ...REGRA_VAZIA,
  weekdays: [],
  week_positions: [],
});

const carregar = () => {
  const u = props.unit;
  form.value = {
    name: u?.name ?? '',
    zip_code: formatarCep(u?.zip_code ?? ''),
    city: u?.city ?? '',
    state: u?.state ?? '',
    address: u?.address ?? '',
    address_number: u?.address_number ?? '',
    phone: formatarTelefone(u?.phone ?? ''),
    timezone: u?.timezone ?? 'America/Sao_Paulo',
    notes: u?.notes ?? '',
    applies_to_inboxes: u?.applies_to_inboxes ?? false,
  };
  coordenadas.value =
    u?.latitude != null && u?.longitude != null
      ? `${u.latitude}, ${u.longitude}`
      : '';
  const grade = u?.working_hours?.length ? u.working_hours : GRADE_PADRAO;
  // Guarda o id de cada dia: sem ele o nested attributes cria linha nova em vez de
  // atualizar a existente, e o índice único do par (unidade, dia) recusa o salvar.
  horaIds.value = Object.fromEntries(
    grade.filter(h => h.id).map(h => [h.day_of_week, h.id])
  );
  // A pausa viaja junto do slot (`breakFrom`/`breakTo`) porque é o BusinessDay que a
  // edita; os helpers compartilhados com a caixa de entrada seguem sem saber dela.
  const porDia = Object.fromEntries(
    grade.map(hora => [hora.day_of_week, hora])
  );
  timeSlots.value = timeSlotParse(grade).map(slot => {
    const hora = porDia[slot.day] || {};
    const temPausa =
      hora.break_start_hour !== null && hora.break_start_hour !== undefined;
    return {
      ...slot,
      breakFrom: temPausa
        ? getTime(hora.break_start_hour, hora.break_start_minutes)
        : '',
      breakTo: temPausa
        ? getTime(hora.break_end_hour, hora.break_end_minutes)
        : '',
    };
  });
  selectedInboxIds.value = [...(u?.inbox_ids ?? [])];
  rules.value = (u?.exceptions ?? []).map(regra => ({ ...regra }));
  novaRegra.value = rascunhoLimpo();
};
// Foto do formulario como ele abriu: e ela que responde "tem alteracao nao salva?" quando o modal
// tenta fechar (o woot-modal desmonta o formulario antes de avisar, entao quem pergunta e a tela).
const instantaneo = ref('');
const estadoAtual = () =>
  JSON.stringify({
    form: form.value,
    coordenadas: coordenadas.value,
    timeSlots: timeSlots.value,
    selectedInboxIds: [...selectedInboxIds.value].sort(),
    rules: rules.value,
  });
const tirarFoto = () => {
  instantaneo.value = estadoAtual();
};

carregar();
tirarFoto();
watch(
  () => props.unit,
  () => {
    carregar();
    tirarFoto();
  }
);

const timezones = timeZoneOptions();
const nomeInvalido = computed(() => !form.value.name.trim());

const cepBuscando = ref(false);
const cepNaoEncontrado = ref(false);

// ViaCEP: público, sem chave e o que todo cadastro brasileiro usa. Preenche endereço, cidade e
// estado — NÃO a coordenada: o CEP devolve a rua, não a porta, e o centro de um CEP fica a
// quarteirões da loja. O pin exato continua sendo colado à mão.
//
// Falhar aqui não pode travar o cadastro: sem rede, os campos seguem editáveis à mão.
const buscarCep = async digitos => {
  cepBuscando.value = true;
  cepNaoEncontrado.value = false;
  try {
    const resposta = await fetch(`https://viacep.com.br/ws/${digitos}/json/`);
    const dados = await resposta.json();
    if (dados.erro) {
      cepNaoEncontrado.value = true;
      return;
    }
    // O número da casa o ViaCEP não tem: fica com o admin completar.
    form.value.address =
      [dados.logradouro, dados.bairro].filter(Boolean).join(' - ') ||
      form.value.address;
    form.value.city = dados.localidade || form.value.city;
    form.value.state = dados.uf || form.value.state;
  } catch (e) {
    cepNaoEncontrado.value = true;
  } finally {
    cepBuscando.value = false;
  }
};

// Dispara sozinho quando o CEP fica completo — com ou sem o traço, colado ou digitado.
watch(
  () => form.value.zip_code,
  valor => {
    const digitos = (valor || '').replace(/\D/g, '');
    cepNaoEncontrado.value = false;
    if (digitos.length === 8) buscarCep(digitos);
  }
);

// Aceita "-15.601, -56.097" e também "-15,601 -56,097": o Google Maps copia com ponto, mas quem
// digita à mão num teclado brasileiro usa vírgula decimal. Vazio é ausência legítima, não erro.
const parCoordenada = computed(() => {
  const cru = coordenadas.value.trim();
  if (!cru) return null;

  const numeros = cru
    .replace(/,(\d)/g, '.$1')
    .split(/[\s,;]+/)
    .filter(Boolean)
    .map(Number);

  if (numeros.length !== 2 || numeros.some(Number.isNaN)) return false;

  const [lat, lng] = numeros;
  const naFaixa = Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  return naFaixa ? { latitude: lat, longitude: lng } : false;
});

const coordenadaInvalida = computed(() => parCoordenada.value === false);
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

// Segunda a sexta costuma ser tudo igual: preenche um dia, copia, e ajusta so o que foge. Copia
// para os dias ABERTOS — fim de semana fechado continua fechado.
const copiarParaOsDemaisDias = origem => {
  const { slots, copiados } = copiarHorarioParaDias(timeSlots.value, origem);
  timeSlots.value = slots;
  useAlert(t('UNITS_MGMT.FORM.HOURS.COPIED', { count: copiados }));
};

// --- regras de agenda --------------------------------------------------------------

const categorias = computed(() =>
  CATEGORIAS.map(valor => ({
    value: valor,
    label: t(`UNITS_MGMT.FORM.RULES.CATEGORY.${valor.toUpperCase()}`),
  }))
);

// O atalho se NOMEIA pela data escolhida ("toda segunda-feira", "em 31 de agosto") e
// preenche os campos que já existem — nenhuma coluna nova. "Personalizar" abre o
// painel detalhado, que continua sendo a fonte de tudo.
const ATALHOS = [
  'nao_repete',
  'todos_os_dias',
  'dias_uteis',
  'semanal',
  'mensal_posicao',
  'anual',
  'personalizar',
];

const atalho = ref('nao_repete');

const dataDoRascunho = computed(() =>
  novaRegra.value.starts_on
    ? new Date(`${novaRegra.value.starts_on}T12:00:00`)
    : null
);

// -1 = última do mês, como no banco. É o que faz "última segunda" existir.
const posicaoDaData = computed(() => {
  const data = dataDoRascunho.value;
  if (!data) return 1;
  const ultimoDia = new Date(
    data.getFullYear(),
    data.getMonth() + 1,
    0
  ).getDate();
  return data.getDate() > ultimoDia - 7 ? -1 : Math.ceil(data.getDate() / 7);
});

const porIntl = opcoes =>
  dataDoRascunho.value
    ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), opcoes).format(
        dataDoRascunho.value
      )
    : '';

const atalhos = computed(() => {
  const dia = porIntl({ weekday: 'long' });
  const diaEMes = porIntl({ day: 'numeric', month: 'long' });
  const posicao = t(
    `UNITS_MGMT.FORM.RULES.SHORTCUTS.POSITION_${
      posicaoDaData.value === -1 ? 'LAST' : posicaoDaData.value
    }`
  );
  return ATALHOS.map(valor => ({
    value: valor,
    label: t(`UNITS_MGMT.FORM.RULES.SHORTCUTS.${valor.toUpperCase()}`, {
      dia,
      diaEMes,
      posicao,
    }),
  }));
});

const RECEITAS = {
  nao_repete: () => ({
    frequency: 'nao_repete',
    weekdays: [],
    week_positions: [],
  }),
  todos_os_dias: () => ({
    frequency: 'semanal',
    weekdays: [0, 1, 2, 3, 4, 5, 6],
    week_positions: [],
  }),
  dias_uteis: () => ({
    frequency: 'semanal',
    weekdays: [1, 2, 3, 4, 5],
    week_positions: [],
  }),
  semanal: data => ({
    frequency: 'semanal',
    weekdays: data ? [data.getDay()] : [],
    week_positions: [],
  }),
  mensal_posicao: (data, posicao) => ({
    frequency: 'mensal',
    mensalPor: 'posicao',
    mensalUltimoDia: false,
    weekdays: data ? [data.getDay()] : [],
    week_positions: [posicao],
  }),
  anual: () => ({ frequency: 'anual', weekdays: [], week_positions: [] }),
};

const aplicarAtalho = valor => {
  atalho.value = valor;
  const rascunho = novaRegra.value;

  // Personalizar não mexe em nada: só revela o painel com o que já está configurado.
  if (valor === 'personalizar') {
    if (rascunho.frequency === 'nao_repete') rascunho.frequency = 'semanal';
    return;
  }

  Object.assign(
    rascunho,
    RECEITAS[valor](dataDoRascunho.value, posicaoDaData.value),
    {
      repeat_interval: 1,
      termino: 'nunca',
      until_date: '',
    }
  );
};

// Trocar a data reescreve o atalho que depende dela — "toda segunda" vira "toda
// quarta" se a data mudar, como no Google.
watch(
  () => novaRegra.value.starts_on,
  () => {
    if (['semanal', 'mensal_posicao', 'anual'].includes(atalho.value)) {
      aplicarAtalho(atalho.value);
    }
  }
);

// Só a véspera: feriado de filial se resolve no dia anterior, e três opções para a
// mesma decisão era escolha demais para quem só quer ser avisado.
const lembretes = computed(() => [
  { value: '', label: t('UNITS_MGMT.FORM.RULES.REMINDER.NONE') },
  { value: 1, label: t('UNITS_MGMT.FORM.RULES.REMINDER.ONE_DAY') },
]);

// Dentro do "Personalizar" a frequência é a UNIDADE do intervalo — "a cada 1
// semana(s)" —, como no Google. Sem "não repete": ali dentro a regra já repete.
const unidadesDeRepeticao = computed(() =>
  FREQUENCIAS.filter(valor => valor !== 'nao_repete').map(valor => ({
    value: valor,
    label: t(`UNITS_MGMT.FORM.RULES.REPEAT.UNIT_${valor.toUpperCase()}`),
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
        ? [rascunho.mensalUltimoDia ? -1 : Number(rascunho.month_day)]
        : [],
    until_date: null,
    reminder_days_before: Number(rascunho.reminder_days_before) || null,
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

// Frase humana da recorrência — é o que a lista mostra no lugar de uma data solta. `quando` é
// o dia em que a regra cai no ano que está na tela: é ele que faz a anual dizer 25/12/2027
// quando o calendário está em 2027, em vez de repetir para sempre o ano em que foi criada.
const resumoDaRegra = (regra, quando) => {
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
    frase = t(`${chave}.YEARLY`, {
      data: dataLegivel(quando ? comoTextoISO(quando) : regra.starts_on),
    });
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

// Caminho de volta: a regra gravada vira rascunho de novo quando se clica nela.
const comoRascunho = regra => ({
  ...rascunhoLimpo(),
  name: regra.name,
  category: regra.category,
  closed_all_day: regra.closed_all_day,
  from:
    regra.open_hour === null || regra.open_hour === undefined
      ? '08:00'
      : getTime(regra.open_hour, regra.open_minutes),
  to:
    regra.close_hour === null || regra.close_hour === undefined
      ? '12:00'
      : getTime(regra.close_hour, regra.close_minutes),
  starts_on: regra.starts_on,
  temPeriodo: !!regra.ends_on,
  ends_on: regra.ends_on || '',
  frequency: regra.frequency,
  repeat_interval: regra.repeat_interval,
  weekdays: [...regra.weekdays],
  mensalPor: regra.month_days.length ? 'dia_do_mes' : 'posicao',
  month_day: regra.month_days[0] > 0 ? regra.month_days[0] : 1,
  mensalUltimoDia: regra.month_days.includes(-1),
  week_positions: [...regra.week_positions],
  termino: regra.until_date ? 'data' : 'nunca',
  until_date: regra.until_date || '',
  reminder_days_before: regra.reminder_days_before ?? '',
});

const escolherDia = iso => {
  editandoIndex.value = -1;
  novaRegra.value = { ...rascunhoLimpo(), starts_on: iso };
};

const editarRegra = index => {
  editandoIndex.value = index;
  novaRegra.value = comoRascunho(rules.value[index]);
  // Regra existente abre no painel detalhado: é lá que ela aparece inteira, sem a
  // tela ter que adivinhar de qual atalho ela veio.
  atalho.value =
    novaRegra.value.frequency === 'nao_repete' ? 'nao_repete' : 'personalizar';
};

const fecharPainel = () => {
  editandoIndex.value = -1;
  novaRegra.value = rascunhoLimpo();
  atalho.value = 'nao_repete';
};

const salvarRegra = () => {
  if (!podeAdicionar.value) return;
  const regra = comoRegra(novaRegra.value);
  if (editandoIndex.value > -1)
    rules.value.splice(editandoIndex.value, 1, regra);
  else rules.value.push(regra);
  fecharPainel();
};

// O backend substitui o conjunto inteiro, então remover é tirar da lista: o que
// sobra é o que fica gravado.
const removerRegra = index => {
  rules.value.splice(index, 1);
  if (editandoIndex.value === index) fecharPainel();
};

const diaEscolhido = computed(() => novaRegra.value.starts_on);

const diaPorExtenso = computed(() => {
  if (!diaEscolhido.value) return '';
  return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(new Date(`${diaEscolhido.value}T12:00:00`));
});

// A grade da semana no formato que o calendário entende (dia fechado fica marcado).
const gradeParaCalendario = computed(() => timeSlotTransform(timeSlots.value));

// Em que dia a regra cai no ano pedido — `null` quando ela não cai nele. Pergunta pela PRÓPRIA
// recorrência, em vez de olhar o `starts_on`: a anual de 25/12/2026 cai em 2030, e a semanal
// só até o `until_date`. É a mesma máquina que desenha o calendário, então a lista e a grade
// nunca discordam.
const ocorrenciaNoAno = (regra, ano) => {
  const [primeira] = proximasOcorrencias(regra, 1, new Date(ano, 0, 1, 12));
  return primeira && primeira.getFullYear() === ano ? primeira : null;
};

// Só o ano que está na tela: com os feriados nacionais de cinco anos à frente, a lista inteira
// viraria uma parede de datas que ninguém lê. Virou o ano no calendário, a lista vira junto —
// e na ORDEM daquele ano, não na ordem em que as regras foram criadas. O `index` continua
// sendo a posição em `rules`: é por ele que se edita e apaga.
const regrasVisiveis = computed(() =>
  rules.value
    .map(regra => ({ regra, quando: ocorrenciaNoAno(regra, anoVisivel.value) }))
    .filter(({ quando }) => !!quando)
    .sort((a, b) => a.quando - b.quando)
    .map(({ regra, quando }) => ({
      ...regra,
      index: rules.value.indexOf(regra),
      resumo: resumoDaRegra(regra, quando),
      faixa: faixaDaRegra(regra),
      cor: COR_DA_CATEGORIA[regra.category] || COR_DA_CATEGORIA.feriado,
      rotulo: t(
        `UNITS_MGMT.FORM.RULES.CATEGORY.${regra.category.toUpperCase()}`
      ),
    }))
);

const onSubmit = () => {
  if (nomeInvalido.value || gradeInvalida.value || coordenadaInvalida.value)
    return;
  emit('submit', {
    ...form.value,
    // `null` e não `''`: string vazia em coluna decimal do Rails vira 0.0, e o ponto (0,0) fica
    // no Golfo da Guiné — uma unidade "sem pin" passaria a ser a mais próxima de todo mundo.
    latitude: parCoordenada.value ? parCoordenada.value.latitude : null,
    longitude: parCoordenada.value ? parCoordenada.value.longitude : null,
    inbox_ids: selectedInboxIds.value,
    working_hours_attributes: timeSlotTransform(timeSlots.value).map(hora => {
      const slot = timeSlots.value.find(item => item.day === hora.day_of_week);
      const comPausa =
        !hora.closed_all_day && !!slot?.breakFrom && !!slot?.breakTo;
      const [inicioHora, inicioMinuto] = comPausa
        ? emHoraEMinuto(slot.breakFrom)
        : [null, null];
      const [fimHora, fimMinuto] = comPausa
        ? emHoraEMinuto(slot.breakTo)
        : [null, null];
      return {
        ...hora,
        id: horaIds.value[hora.day_of_week],
        break_start_hour: inicioHora,
        break_start_minutes: inicioMinuto,
        break_end_hour: fimHora,
        break_end_minutes: fimMinuto,
      };
    }),
    exceptions: rules.value,
  });
};

// A tela precisa das duas coisas para perguntar antes de descartar: se mudou algo e como salvar.
defineExpose({
  temAlteracoes: () => estadoAtual() !== instantaneo.value,
  salvar: () => onSubmit(),
});
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
          :model-value="form.phone"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.PHONE.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.PHONE.PLACEHOLDER')"
          @update:model-value="valor => (form.phone = formatarTelefone(valor))"
        />
      </div>
      <woot-input
        :model-value="form.zip_code"
        class="mb-0"
        :label="t('UNITS_MGMT.FORM.ZIP_CODE.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.ZIP_CODE.PLACEHOLDER')"
        @update:model-value="valor => (form.zip_code = formatarCep(valor))"
      />
      <p
        class="m-0 text-label-small"
        :class="cepNaoEncontrado ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        {{
          cepBuscando
            ? t('UNITS_MGMT.FORM.ZIP_CODE.SEARCHING')
            : cepNaoEncontrado
              ? t('UNITS_MGMT.FORM.ZIP_CODE.NOT_FOUND')
              : t('UNITS_MGMT.FORM.ZIP_CODE.HELP')
        }}
      </p>
      <div class="grid gap-4 sm:grid-cols-4">
        <woot-input
          v-model="form.address"
          class="mb-0 sm:col-span-3"
          :label="t('UNITS_MGMT.FORM.ADDRESS.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.ADDRESS.PLACEHOLDER')"
        />
        <!-- Texto, e nao numero: precisa aceitar "S/N", "123-A" e "Km 12". O ViaCEP nunca toca aqui. -->
        <woot-input
          v-model="form.address_number"
          class="mb-0"
          :label="t('UNITS_MGMT.FORM.ADDRESS_NUMBER.LABEL')"
          :placeholder="t('UNITS_MGMT.FORM.ADDRESS_NUMBER.PLACEHOLDER')"
        />
      </div>
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
      <woot-input
        v-model="coordenadas"
        class="mb-0"
        :class="{ error: coordenadaInvalida }"
        :label="t('UNITS_MGMT.FORM.COORDINATES.LABEL')"
        :placeholder="t('UNITS_MGMT.FORM.COORDINATES.PLACEHOLDER')"
      />
      <p
        class="m-0 text-label-small"
        :class="coordenadaInvalida ? 'text-n-ruby-11' : 'text-n-slate-11'"
      >
        {{
          coordenadaInvalida
            ? t('UNITS_MGMT.FORM.COORDINATES.ERROR')
            : t('UNITS_MGMT.FORM.COORDINATES.HELP')
        }}
      </p>
    </section>

    <section>
      <span class="text-heading-3">{{
        t('UNITS_MGMT.FORM.INBOXES.LABEL')
      }}</span>
      <p class="mt-0.5 mb-2 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.INBOXES.HELP') }}
      </p>
      <label class="flex gap-2 items-start mb-3 cursor-pointer w-fit">
        <input
          v-model="form.applies_to_inboxes"
          type="checkbox"
          class="m-0 mt-0.5"
        />
        <span class="flex flex-col">
          <span class="text-sm text-n-slate-12">
            {{ t('UNITS_MGMT.FORM.INBOXES.APPLIES.LABEL') }}
          </span>
          <span class="text-n-slate-11 text-label-small">
            {{ t('UNITS_MGMT.FORM.INBOXES.APPLIES.HELP') }}
          </span>
        </span>
      </label>
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
            show-break
            @update="dados => onSlotUpdate(slot.day, dados)"
          >
            <template #acoes>
              <Button
                v-if="slot.from && slot.to"
                link
                slate
                xs
                type="button"
                :label="t('UNITS_MGMT.FORM.HOURS.COPY')"
                @click.prevent="copiarParaOsDemaisDias(slot)"
              />
            </template>
          </BusinessDay>
        </tbody>
      </table>
    </section>

    <section>
      <span class="text-heading-3">{{
        t('UNITS_MGMT.FORM.CALENDAR.LABEL')
      }}</span>
      <p class="mt-0.5 mb-3 text-n-slate-11 text-label-small">
        {{ t('UNITS_MGMT.FORM.CALENDAR.HELP') }}
      </p>

      <UnitCalendar
        :rules="rules"
        :working-hours="gradeParaCalendario"
        :selected="diaEscolhido"
        :cores="COR_DA_CATEGORIA"
        @select="escolherDia"
        @edit="editarRegra"
        @ano="anoVisivel = $event"
      />

      <div
        v-if="diaEscolhido"
        class="flex flex-col gap-4 p-4 mt-3 border rounded-xl border-n-brand/40 bg-n-solid-1"
      >
        <div class="flex items-center justify-between gap-3">
          <span class="text-heading-3 text-n-slate-12 first-letter:uppercase">
            {{ diaPorExtenso }}
          </span>
          <div class="flex items-center gap-1">
            <Button
              v-if="editandoIndex > -1"
              ghost
              ruby
              xs
              icon="i-lucide-trash-2"
              :title="t('UNITS_MGMT.FORM.RULES.DELETE')"
              @click.prevent="removerRegra(editandoIndex)"
            />
            <Button
              ghost
              slate
              xs
              icon="i-lucide-x"
              :title="t('UNITS_MGMT.FORM.RULES.CLOSE')"
              @click.prevent="fecharPainel"
            />
          </div>
        </div>
        <div class="grid gap-3 sm:grid-cols-[minmax(0,13rem)_1fr]">
          <div class="flex flex-col gap-1">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.CATEGORY.LABEL') }}
            </span>
            <NextSelect
              v-model="novaRegra.category"
              :options="categorias"
              :class="SELETOR"
            />
          </div>
          <div class="flex flex-col gap-1">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.EXCEPTIONS.NAME') }}
            </span>
            <input
              v-model="novaRegra.name"
              type="text"
              :class="CAMPO"
              :placeholder="t('UNITS_MGMT.FORM.EXCEPTIONS.NAME_PLACEHOLDER')"
            />
          </div>
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
              class="w-28"
              :class="[CAMPO]"
            />
            <span class="text-n-slate-11">–</span>
            <input
              v-model="novaRegra.to"
              type="time"
              class="w-28"
              :class="[CAMPO]"
            />
          </div>
        </div>

        <div class="flex flex-wrap items-end gap-x-4 gap-y-3">
          <div class="flex flex-col gap-1 w-60">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.REPEAT.LABEL') }}
            </span>
            <NextSelect
              :model-value="atalho"
              :options="atalhos"
              :class="SELETOR"
              @update:model-value="aplicarAtalho"
            />
          </div>
          <div class="flex flex-col gap-1 w-52">
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.REMINDER.LABEL') }}
            </span>
            <NextSelect
              v-model="novaRegra.reminder_days_before"
              :options="lembretes"
              :class="SELETOR"
            />
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
          <div
            v-if="novaRegra.frequency === 'nao_repete' && novaRegra.temPeriodo"
            class="flex flex-col gap-1 w-44"
          >
            <span class="text-heading-3">
              {{ t('UNITS_MGMT.FORM.RULES.ENDS_ON') }}
            </span>
            <input v-model="novaRegra.ends_on" type="date" :class="CAMPO" />
          </div>
        </div>

        <div
          v-if="
            atalho === 'personalizar' && novaRegra.frequency !== 'nao_repete'
          "
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
              :class="CAMPO_ESTREITO"
            />
            <NextSelect
              v-model="novaRegra.frequency"
              :options="unidadesDeRepeticao"
              class="w-36 [&>select]:h-10 [&>select]:w-full"
            />
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
              class="flex flex-wrap items-center gap-2"
            >
              <span class="text-sm text-n-slate-11">
                {{ t('UNITS_MGMT.FORM.RULES.MONTHLY.DAY') }}
              </span>
              <input
                v-model="novaRegra.month_day"
                type="number"
                min="1"
                max="31"
                :disabled="novaRegra.mensalUltimoDia"
                class="disabled:opacity-50"
                :class="[CAMPO_ESTREITO]"
              />
              <label class="flex items-center gap-2 mb-0 cursor-pointer">
                <input
                  v-model="novaRegra.mensalUltimoDia"
                  type="checkbox"
                  class="m-0"
                />
                <span class="text-sm text-n-slate-12">
                  {{ t('UNITS_MGMT.FORM.RULES.MONTHLY.LAST_DAY') }}
                </span>
              </label>
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
              class="w-44"
              :class="[CAMPO]"
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
            :label="
              editandoIndex > -1
                ? t('UNITS_MGMT.FORM.RULES.SAVE')
                : t('UNITS_MGMT.FORM.RULES.ADD')
            "
            sm
            :disabled="!podeAdicionar"
            @click.prevent="salvarRegra"
          />
        </div>

        <p v-if="erroDaRegra" class="m-0 text-n-ruby-9 text-label-small">
          {{ erroDaRegra }}
        </p>
      </div>

      <p
        v-if="rules.length && !regrasVisiveis.length"
        class="mt-3 mb-0 text-n-slate-11 text-label-small"
      >
        {{
          t('UNITS_MGMT.FORM.CALENDAR.RULES_EMPTY_YEAR', { ano: anoVisivel })
        }}
      </p>

      <div v-if="regrasVisiveis.length" class="mt-3">
        <span class="text-n-slate-11 text-label-small">
          {{ t('UNITS_MGMT.FORM.CALENDAR.RULES_TITLE', { ano: anoVisivel }) }}
        </span>
        <ul
          class="p-0 mx-0 mt-1 mb-0 list-none border rounded-lg divide-y divide-n-weak border-n-weak"
        >
          <li
            v-for="regra in regrasVisiveis"
            :key="regra.index"
            class="flex flex-wrap items-center gap-3 px-3 py-2 cursor-pointer hover:bg-n-alpha-1"
            @click="editarRegra(regra.index)"
          >
            <span
              class="px-2 py-1 rounded-lg text-label-small whitespace-nowrap"
              :class="regra.cor"
            >
              {{ regra.rotulo }}
            </span>
            <span class="text-sm font-medium text-n-slate-12">
              {{ regra.name }}
            </span>
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
              icon="i-woot-edit-pen"
              :title="t('UNITS_MGMT.FORM.RULES.EDIT')"
              @click.stop.prevent="editarRegra(regra.index)"
            />
            <Button
              ghost
              slate
              xs
              icon="i-lucide-trash-2"
              :title="t('UNITS_MGMT.FORM.RULES.DELETE')"
              @click.stop.prevent="removerRegra(regra.index)"
            />
          </li>
        </ul>
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
        :disabled="
          nomeInvalido || gradeInvalida || coordenadaInvalida || isSaving
        "
      />
    </div>
  </form>
</template>
