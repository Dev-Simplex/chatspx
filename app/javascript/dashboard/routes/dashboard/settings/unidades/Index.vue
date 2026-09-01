<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import unidadesAPI from 'dashboard/api/unidades';
import unidadeExcecoesAPI from 'dashboard/api/unidadeExcecoes';

const { t } = useI18n();

// A aba Unidades é LEITURA por decisão de fase (§9.1 do contrato): endereço muda uma vez por ano
// e a carga é por rake. Ela existe aqui porque sem a lista não há de onde escolher o alvo de uma
// exceção, nem como conferir se a carga entrou certa.
const ABAS = ['unidades', 'excecoes'];
const abaAtiva = ref('unidades');

const unidades = ref([]);
const etiquetas = ref([]);
const excecoes = ref([]);
const carregando = ref(false);
const salvando = ref(false);

// 2 = uma unidade · 1 = uma etiqueta · 0 = a conta inteira. Mesma escala que o motor usa para
// decidir qual exceção vence.
const ALCANCE_CONTA = 'conta';
const ESTADO_FECHADA = 'fechada';
const ESTADO_HORARIO = 'horario';
const ESTADO_NORMAL = 'normal';

const formularioVazio = () => ({
  alvo: ALCANCE_CONTA,
  dataInicio: '',
  dataFim: '',
  estado: ESTADO_FECHADA,
  abre: '',
  fecha: '',
  motivo: '',
});

const formulario = ref(formularioVazio());

const ordemLeitura = [1, 2, 3, 4, 5, 6, 0];

const rotuloDia = dia => t(`UNIDADES.DIAS.${dia}`);

// Dia ausente da grade cai no default `cadastrado: false` — que a tela mostra como "não
// cadastrado", e nunca como "fechada". São coisas diferentes e a distinção é o que impede a
// tela de inventar horário.
const diaDe = (unidade, dia) =>
  unidade.grade.find(linha => linha.dia_semana === dia) || {
    cadastrado: false,
    faixas: [],
  };

// Opções do alvo: a conta inteira, cada etiqueta e cada unidade. É a mesma ordem de
// especificidade do contrato — do mais amplo para o mais específico.
const opcoesAlvo = computed(() => [
  { valor: ALCANCE_CONTA, rotulo: t('UNIDADES.EXCECOES.ALVO_CONTA') },
  ...etiquetas.value.map(etiqueta => ({
    valor: `etiqueta:${etiqueta}`,
    rotulo: t('UNIDADES.EXCECOES.ALVO_ETIQUETA', { etiqueta }),
  })),
  ...unidades.value.map(unidade => ({
    valor: `unidade:${unidade.id}`,
    rotulo: unidade.nome,
  })),
]);

const carregar = async () => {
  carregando.value = true;
  try {
    const [respostaUnidades, respostaExcecoes] = await Promise.all([
      unidadesAPI.getAll(),
      unidadeExcecoesAPI.getAll(),
    ]);
    unidades.value = respostaUnidades.data.unidades || [];
    etiquetas.value = respostaUnidades.data.etiquetas || [];
    excecoes.value = respostaExcecoes.data || [];
  } catch (error) {
    useAlert(t('UNIDADES.ERRO_CARREGAR'));
  } finally {
    carregando.value = false;
  }
};

const corpoDaExcecao = () => {
  const { alvo, estado } = formulario.value;
  const corpo = {
    data_inicio: formulario.value.dataInicio,
    data_fim: formulario.value.dataFim,
    fechada: estado === ESTADO_FECHADA,
    motivo: formulario.value.motivo,
  };

  if (alvo.startsWith('etiqueta:')) corpo.etiqueta = alvo.slice('etiqueta:'.length);
  if (alvo.startsWith('unidade:')) corpo.unidade_id = alvo.slice('unidade:'.length);

  // Sem horário e sem fechar significa "abre no horário de sempre" — é como uma unidade escapa
  // de um fechamento de etiqueta sem repetir a grade inteira.
  if (estado === ESTADO_HORARIO) {
    corpo.abre = formulario.value.abre;
    corpo.fecha = formulario.value.fecha;
  }

  return corpo;
};

const formularioValido = computed(() => {
  const { dataInicio, dataFim, estado, abre, fecha } = formulario.value;
  if (!dataInicio || !dataFim) return false;
  if (dataFim < dataInicio) return false;
  if (estado === ESTADO_HORARIO && (!abre || !fecha)) return false;
  return true;
});

const criarExcecao = async () => {
  salvando.value = true;
  try {
    await unidadeExcecoesAPI.create(corpoDaExcecao());
    formulario.value = formularioVazio();
    await carregar();
    useAlert(t('UNIDADES.EXCECOES.CRIADA'));
  } catch (error) {
    useAlert(t('UNIDADES.EXCECOES.ERRO_CRIAR'));
  } finally {
    salvando.value = false;
  }
};

const apagarExcecao = async id => {
  try {
    await unidadeExcecoesAPI.delete(id);
    excecoes.value = excecoes.value.filter(excecao => excecao.id !== id);
    useAlert(t('UNIDADES.EXCECOES.APAGADA'));
  } catch (error) {
    useAlert(t('UNIDADES.EXCECOES.ERRO_APAGAR'));
  }
};

const alcanceDaExcecao = excecao => {
  if (excecao.unidade_nome) return excecao.unidade_nome;
  if (excecao.etiqueta)
    return t('UNIDADES.EXCECOES.ALVO_ETIQUETA', { etiqueta: excecao.etiqueta });
  return t('UNIDADES.EXCECOES.ALVO_CONTA');
};

const periodoDaExcecao = excecao =>
  excecao.data_inicio === excecao.data_fim
    ? excecao.data_inicio
    : `${excecao.data_inicio} — ${excecao.data_fim}`;

onMounted(carregar);
</script>

<template>
  <div class="flex-1 overflow-auto bg-n-solid-1">
    <div class="max-w-6xl px-6 py-8 mx-auto">
      <h1 class="mb-1 text-2xl font-semibold text-n-slate-12">
        {{ $t('UNIDADES.TITULO') }}
      </h1>
      <p class="mb-6 text-sm text-n-slate-11">
        {{ $t('UNIDADES.DESCRICAO') }}
      </p>

      <div class="flex gap-1 mb-6 border-b border-n-weak">
        <button
          v-for="aba in ABAS"
          :key="aba"
          class="px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            abaAtiva === aba
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="abaAtiva = aba"
        >
          {{ $t(`UNIDADES.ABAS.${aba.toUpperCase()}`) }}
        </button>
      </div>

      <p v-if="carregando" class="text-sm text-n-slate-11">
        {{ $t('UNIDADES.CARREGANDO') }}
      </p>

      <!-- Aba Unidades — leitura -->
      <div v-else-if="abaAtiva === 'unidades'">
        <p v-if="!unidades.length" class="text-sm text-n-slate-11">
          {{ $t('UNIDADES.VAZIO') }}
        </p>
        <div
          v-for="unidade in unidades"
          v-else
          :key="unidade.id"
          class="p-4 mb-3 border rounded-lg bg-white dark:bg-n-solid-2 border-n-weak"
        >
          <div class="flex flex-wrap items-baseline gap-2">
            <span class="font-medium text-n-slate-12">{{ unidade.nome }}</span>
            <span class="text-sm text-n-slate-11">
              {{ unidade.cidade }}<template v-if="unidade.uf">/{{ unidade.uf }}</template>
            </span>
            <span
              v-if="!unidade.ativa"
              class="px-2 py-0.5 text-xs rounded bg-n-solid-3 text-n-slate-11"
            >
              {{ $t('UNIDADES.INATIVA') }}
            </span>
          </div>

          <p v-if="unidade.endereco" class="mt-1 text-sm text-n-slate-11">
            {{ unidade.endereco }}
          </p>
          <p v-if="unidade.telefone" class="text-sm text-n-slate-11">
            {{ unidade.telefone }}
          </p>

          <div v-if="unidade.etiquetas.length" class="flex flex-wrap gap-1 mt-2">
            <span
              v-for="etiqueta in unidade.etiquetas"
              :key="etiqueta"
              class="px-2 py-0.5 text-xs rounded bg-n-solid-3 text-n-slate-11"
            >
              {{ etiqueta }}
            </span>
          </div>

          <div class="grid grid-cols-2 gap-x-6 gap-y-1 mt-3 sm:grid-cols-4">
            <div
              v-for="dia in ordemLeitura"
              :key="dia"
              class="flex justify-between gap-2 text-sm"
            >
              <span class="text-n-slate-11">{{ rotuloDia(dia) }}</span>
              <span class="text-n-slate-12">
                <!-- "não cadastrado" e "fechada" são coisas diferentes: a primeira é ausência
                     de dado, e dizer "fechada" no lugar dela seria inventar. -->
                <template v-if="!diaDe(unidade, dia).cadastrado">
                  {{ $t('UNIDADES.NAO_CADASTRADO') }}
                </template>
                <template v-else-if="!diaDe(unidade, dia).faixas.length">
                  {{ $t('UNIDADES.FECHADA') }}
                </template>
                <template v-else>
                  {{ diaDe(unidade, dia).faixas.join(', ') }}
                </template>
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- Aba Exceções — escrita -->
      <div v-else>
        <div
          class="p-4 mb-6 border rounded-lg bg-white dark:bg-n-solid-2 border-n-weak"
        >
          <h2 class="mb-3 text-sm font-medium text-n-slate-12">
            {{ $t('UNIDADES.EXCECOES.NOVA') }}
          </h2>

          <div class="grid gap-3 sm:grid-cols-2">
            <label class="text-sm">
              <span class="block mb-1 text-n-slate-11">
                {{ $t('UNIDADES.EXCECOES.ALVO') }}
              </span>
              <select
                v-model="formulario.alvo"
                class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              >
                <option
                  v-for="opcao in opcoesAlvo"
                  :key="opcao.valor"
                  :value="opcao.valor"
                >
                  {{ opcao.rotulo }}
                </option>
              </select>
            </label>

            <label class="text-sm">
              <span class="block mb-1 text-n-slate-11">
                {{ $t('UNIDADES.EXCECOES.ESTADO') }}
              </span>
              <select
                v-model="formulario.estado"
                class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              >
                <option :value="ESTADO_FECHADA">
                  {{ $t('UNIDADES.EXCECOES.ESTADO_FECHADA') }}
                </option>
                <option :value="ESTADO_HORARIO">
                  {{ $t('UNIDADES.EXCECOES.ESTADO_HORARIO') }}
                </option>
                <option :value="ESTADO_NORMAL">
                  {{ $t('UNIDADES.EXCECOES.ESTADO_NORMAL') }}
                </option>
              </select>
            </label>

            <label class="text-sm">
              <span class="block mb-1 text-n-slate-11">
                {{ $t('UNIDADES.EXCECOES.DATA_INICIO') }}
              </span>
              <input
                v-model="formulario.dataInicio"
                type="date"
                class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              />
            </label>

            <label class="text-sm">
              <span class="block mb-1 text-n-slate-11">
                {{ $t('UNIDADES.EXCECOES.DATA_FIM') }}
              </span>
              <input
                v-model="formulario.dataFim"
                type="date"
                class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              />
            </label>

            <template v-if="formulario.estado === ESTADO_HORARIO">
              <label class="text-sm">
                <span class="block mb-1 text-n-slate-11">
                  {{ $t('UNIDADES.EXCECOES.ABRE') }}
                </span>
                <input
                  v-model="formulario.abre"
                  type="time"
                  class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
                />
              </label>
              <label class="text-sm">
                <span class="block mb-1 text-n-slate-11">
                  {{ $t('UNIDADES.EXCECOES.FECHA') }}
                </span>
                <input
                  v-model="formulario.fecha"
                  type="time"
                  class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
                />
              </label>
            </template>

            <label class="text-sm sm:col-span-2">
              <span class="block mb-1 text-n-slate-11">
                {{ $t('UNIDADES.EXCECOES.MOTIVO') }}
              </span>
              <input
                v-model="formulario.motivo"
                type="text"
                class="w-full px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              />
              <!-- O motivo chega ao cliente pela IA (§9.4), então ele é texto de atendimento,
                   não anotação interna. -->
              <span class="block mt-1 text-xs text-n-slate-10">
                {{ $t('UNIDADES.EXCECOES.MOTIVO_AJUDA') }}
              </span>
            </label>
          </div>

          <button
            class="px-4 py-2 mt-4 text-sm font-medium rounded text-white bg-n-brand disabled:opacity-50"
            :disabled="!formularioValido || salvando"
            @click="criarExcecao"
          >
            {{ $t('UNIDADES.EXCECOES.CRIAR') }}
          </button>
        </div>

        <p v-if="!excecoes.length" class="text-sm text-n-slate-11">
          {{ $t('UNIDADES.EXCECOES.VAZIO') }}
        </p>
        <div
          v-for="excecao in excecoes"
          v-else
          :key="excecao.id"
          class="flex items-start justify-between gap-4 p-3 mb-2 border rounded-lg bg-white dark:bg-n-solid-2 border-n-weak"
        >
          <div class="text-sm">
            <div class="font-medium text-n-slate-12">
              {{ periodoDaExcecao(excecao) }} · {{ alcanceDaExcecao(excecao) }}
            </div>
            <div class="text-n-slate-11">
              <template v-if="excecao.fechada">
                {{ $t('UNIDADES.EXCECOES.ESTADO_FECHADA') }}
              </template>
              <template v-else-if="excecao.horario">{{ excecao.horario }}</template>
              <template v-else>
                {{ $t('UNIDADES.EXCECOES.ESTADO_NORMAL') }}
              </template>
              <template v-if="excecao.motivo"> · {{ excecao.motivo }}</template>
            </div>
          </div>
          <button
            class="text-sm text-n-ruby-11 hover:underline"
            @click="apagarExcecao(excecao.id)"
          >
            {{ $t('UNIDADES.EXCECOES.APAGAR') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
