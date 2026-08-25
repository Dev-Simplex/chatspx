<script>
/**
 * Helpers puros da tela de política do rodízio.
 *
 * Ficam num `<script>` separado (e não dentro do `<script setup>`) porque o
 * setup roda por instância do componente: o que precisa ser testado sem montar
 * a tela tem que morar no escopo do módulo.
 */
export const MODOS = ['rodizio', 'fila', 'online', 'off'];
export const MODOS_OFERECIDOS = ['rodizio', 'fila'];
export const MODOS_POSSE = ['assignee', 'designacao'];

// Espelha os defaults da COLUNA (db/schema.rb, distribuicao_policies) — de proposito. Uma politica
// criada por esta tela tem que se comportar igual a uma criada por `rake spx:distribuicao:policy`;
// divergir aqui faria a mesma configuracao render resultados diferentes conforme a porta de entrada,
// e ninguem olhando a tela desconfiaria. As duas excecoes sao intencionais e comentadas.
export const politicaPadrao = () => ({
  // `ativo` nasce FALSE (a coluna e true): a tela e um formulario em branco, e ligar o motor num
  // time e uma decisao explicita — o estado vazio diz "preencha e salve para ligar".
  ativo: false,
  modo: 'rodizio',
  modo_posse: 'assignee',
  continuidade_ativa: true,
  continuidade_dias: 30,
  sla_assumir_minutos: 30,
  // `repasse_automatico` nasce FALSE (igual a coluna): repassar lead sozinho e comportamento que o
  // gestor precisa pedir, nao herdar.
  repasse_automatico: false,
  max_repasses: 2,
  pool_esgotado_destino_user_id: null,
  gatilho_sem_ia: false,
  pool: [],
});

const paraId = valor => {
  const numero = Number(valor);
  return Number.isFinite(numero) ? numero : null;
};

// Vazio = sem teto. Só isso distingue "não limitei" de "limitei em zero".
export const normalizarCap = valor => {
  if (valor === null || valor === undefined || valor === '') return null;
  const numero = Number(valor);
  return Number.isFinite(numero) ? Math.trunc(numero) : null;
};

/**
 * Casa o pool salvo com os membros que o time tem HOJE.
 * - a ordem do pool salvo é preservada: ela é a ordem em que o rodízio anda;
 * - quem saiu do time some do pool — o rodízio não pode parar num nome que não
 *   atende mais naquela caixa;
 * - quem entrou no time entra no FIM e DESLIGADO: entrar no time não é entrar
 *   no rodízio, alguém tem que ligar a pessoa de propósito.
 */
export const normalizarPool = (members = [], pool = []) => {
  const porId = new Map(
    (members || []).map(membro => [paraId(membro?.id), membro])
  );
  const vistos = new Set();
  const linhas = [];

  (pool || []).forEach(item => {
    const userId = paraId(item?.user_id);
    const membro = porId.get(userId);
    if (userId === null || !membro || vistos.has(userId)) return;
    vistos.add(userId);
    linhas.push({
      user_id: userId,
      name: membro.name || item.name || membro.email || '',
      email: membro.email || '',
      ativo: item.ativo !== false,
      cap: normalizarCap(item.cap),
    });
  });

  (members || []).forEach(membro => {
    const userId = paraId(membro?.id);
    if (userId === null || vistos.has(userId)) return;
    vistos.add(userId);
    linhas.push({
      user_id: userId,
      name: membro.name || membro.email || '',
      email: membro.email || '',
      ativo: false,
      cap: null,
    });
  });

  return linhas;
};

// Troca duas posições; fora dos limites devolve a mesma lista (o botão da ponta
// não faz nada em vez de embaralhar).
export const moverNoPool = (pool, indice, delta) => {
  const lista = pool || [];
  const destino = indice + delta;
  if (indice < 0 || indice >= lista.length) return lista;
  if (destino < 0 || destino >= lista.length) return lista;
  const copia = [...lista];
  [copia[indice], copia[destino]] = [copia[destino], copia[indice]];
  return copia;
};

export const politicaParaForm = (policy, members = []) => {
  const padrao = politicaPadrao();
  if (!policy) return { ...padrao, pool: normalizarPool(members, []) };

  return {
    ativo: !!policy.ativo,
    modo: MODOS.includes(policy.modo) ? policy.modo : padrao.modo,
    modo_posse: MODOS_POSSE.includes(policy.modo_posse)
      ? policy.modo_posse
      : padrao.modo_posse,
    continuidade_ativa: !!policy.continuidade_ativa,
    continuidade_dias: policy.continuidade_dias ?? padrao.continuidade_dias,
    sla_assumir_minutos:
      policy.sla_assumir_minutos ?? padrao.sla_assumir_minutos,
    repasse_automatico: !!policy.repasse_automatico,
    max_repasses: policy.max_repasses ?? padrao.max_repasses,
    pool_esgotado_destino_user_id: policy.pool_esgotado_destino_user_id ?? null,
    gatilho_sem_ia: !!policy.gatilho_sem_ia,
    pool: normalizarPool(members, policy.pool || []),
  };
};

const inteiroPositivo = valor => {
  const numero = Number(valor);
  return Number.isInteger(numero) && numero > 0;
};

export const validarPolitica = (form = {}) => {
  const erros = [];
  const pool = form.pool || [];

  if (!MODOS.includes(form.modo)) erros.push('MODO');
  if (!MODOS_POSSE.includes(form.modo_posse)) erros.push('MODO_POSSE');
  if (!inteiroPositivo(form.sla_assumir_minutos)) erros.push('SLA');

  const repasses = Number(form.max_repasses);
  if (!Number.isInteger(repasses) || repasses < 0) erros.push('MAX_REPASSES');

  if (form.continuidade_ativa && !inteiroPositivo(form.continuidade_dias)) {
    erros.push('CONTINUIDADE_DIAS');
  }

  const capInvalido = pool.some(
    linha =>
      linha.ativo &&
      normalizarCap(linha.cap) !== null &&
      !inteiroPositivo(normalizarCap(linha.cap))
  );
  if (capInvalido) erros.push('CAP');

  // Política ligada com o pool vazio não entrega nada, e o gestor só descobre
  // quando o lead some.
  if (form.ativo && form.modo !== 'off' && !pool.some(linha => linha.ativo)) {
    erros.push('POOL_VAZIO');
  }

  return erros;
};

export const montarPayload = (form = {}) => ({
  ativo: !!form.ativo,
  modo: form.modo,
  modo_posse: form.modo_posse,
  continuidade_ativa: !!form.continuidade_ativa,
  continuidade_dias: Number(form.continuidade_dias),
  sla_assumir_minutos: Number(form.sla_assumir_minutos),
  repasse_automatico: !!form.repasse_automatico,
  max_repasses: Number(form.max_repasses),
  pool_esgotado_destino_user_id: form.pool_esgotado_destino_user_id
    ? Number(form.pool_esgotado_destino_user_id)
    : null,
  gatilho_sem_ia: !!form.gatilho_sem_ia,
  // Manda a lista INTEIRA, inclusive quem está desligado: a posição de quem
  // está fora hoje é a posição que ele retoma quando for religado.
  pool: (form.pool || []).map(linha => ({
    user_id: Number(linha.user_id),
    ativo: !!linha.ativo,
    cap: normalizarCap(linha.cap),
  })),
});
</script>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoPoliciesAPI from 'dashboard/api/distribuicaoPolicies';

defineOptions({ name: 'RodizioPoliticaPage' });

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const loading = ref(true);
const loadError = ref(false);
const salvando = ref(false);
const times = ref([]);
const teamId = ref('');
const membros = ref([]);
const politicaExiste = ref(false);
const form = ref(politicaPadrao());
const erros = ref([]);
const errosServidor = ref([]);
const confirmandoRemocao = ref(false);

const carregarTime = async () => {
  erros.value = [];
  errosServidor.value = [];
  confirmandoRemocao.value = false;
  if (!teamId.value) {
    politicaExiste.value = false;
    membros.value = [];
    form.value = politicaPadrao();
    return;
  }
  loading.value = true;
  loadError.value = false;
  try {
    const { data } = await DistribuicaoPoliciesAPI.show(teamId.value);
    membros.value = data.members || [];
    politicaExiste.value = !!data.policy;
    form.value = politicaParaForm(data.policy, membros.value);
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

const carregarTimes = async () => {
  loading.value = true;
  loadError.value = false;
  try {
    const { data } = await DistribuicaoPoliciesAPI.get();
    times.value = data.teams || [];
    // Conta com um time só não faz o gestor escolher nada: já abre configurado.
    if (!teamId.value && times.value.length === 1) {
      teamId.value = String(times.value[0].id);
      await carregarTime();
    }
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(carregarTimes);

const pool = computed(() => form.value.pool || []);
const temTime = computed(() => !!teamId.value);

// O contrato aceita `online` e `off`, mas essa tela só oferece rodízio e fila.
// Se o time já estiver num modo ligado por console, ele entra na lista para não
// ser sobrescrito em silêncio no primeiro "Salvar".
const modosDisponiveis = computed(() => {
  const atual = form.value.modo;
  return MODOS_OFERECIDOS.includes(atual)
    ? MODOS_OFERECIDOS
    : [...MODOS_OFERECIDOS, atual];
});

// Uma chamada literal por código, e não `t(\`ERRORS.${erro}\`)`: chave montada em
// runtime some do grep e ninguém descobre quando ela é renomeada.
const CHAVES_ERRO = {
  MODO: () => t('AGENTS_RODIZIO.POLICY.ERRORS.MODO'),
  MODO_POSSE: () => t('AGENTS_RODIZIO.POLICY.ERRORS.MODO_POSSE'),
  SLA: () => t('AGENTS_RODIZIO.POLICY.ERRORS.SLA'),
  MAX_REPASSES: () => t('AGENTS_RODIZIO.POLICY.ERRORS.MAX_REPASSES'),
  CONTINUIDADE_DIAS: () => t('AGENTS_RODIZIO.POLICY.ERRORS.CONTINUIDADE_DIAS'),
  CAP: () => t('AGENTS_RODIZIO.POLICY.ERRORS.CAP'),
  POOL_VAZIO: () => t('AGENTS_RODIZIO.POLICY.ERRORS.POOL_VAZIO'),
};

const rotuloErro = erro => (CHAVES_ERRO[erro] ? CHAVES_ERRO[erro]() : erro);

const rotuloModo = modo => {
  if (modo === 'rodizio') return t('AGENTS_RODIZIO.POLICY.ENGINE.MODE_RODIZIO');
  if (modo === 'fila') return t('AGENTS_RODIZIO.POLICY.ENGINE.MODE_FILA');
  return t('AGENTS_RODIZIO.POLICY.ENGINE.MODE_RAW', { modo });
};

const mover = (indice, delta) => {
  form.value.pool = moverNoPool(pool.value, indice, delta);
};

const voltar = () =>
  router.push({
    name: 'agents_rodizio',
    params: { accountId: accountId.value },
  });

const salvar = async () => {
  errosServidor.value = [];
  erros.value = validarPolitica(form.value);
  if (erros.value.length) return;

  salvando.value = true;
  try {
    const { data } = await DistribuicaoPoliciesAPI.upsert(
      teamId.value,
      montarPayload(form.value)
    );
    politicaExiste.value = true;
    form.value = politicaParaForm(data.policy, membros.value);
    useAlert(t('AGENTS_RODIZIO.POLICY.SAVED'));
  } catch (e) {
    errosServidor.value = e?.response?.data?.errors || [];
    useAlert(t('AGENTS_RODIZIO.POLICY.SAVE_ERROR'));
  } finally {
    salvando.value = false;
  }
};

const remover = async () => {
  salvando.value = true;
  try {
    await DistribuicaoPoliciesAPI.delete(teamId.value);
    politicaExiste.value = false;
    form.value = politicaParaForm(null, membros.value);
    confirmandoRemocao.value = false;
    useAlert(t('AGENTS_RODIZIO.POLICY.REMOVED'));
  } catch (e) {
    useAlert(t('AGENTS_RODIZIO.POLICY.REMOVE_ERROR'));
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <div class="flex overflow-y-auto flex-col gap-6 p-6">
    <header class="flex flex-wrap gap-4 justify-between items-end">
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.SUBTITLE') }}
        </p>
      </div>
      <div class="flex gap-2 items-center">
        <select
          v-model="teamId"
          class="px-2 h-9 text-sm bg-white rounded-lg border dark:bg-n-solid-2 border-n-weak text-n-slate-12"
          @change="carregarTime"
        >
          <option value="">
            {{ t('AGENTS_RODIZIO.POLICY.SELECT_TEAM') }}
          </option>
          <option v-for="time in times" :key="time.id" :value="String(time.id)">
            {{ time.name }}
          </option>
        </select>
        <button
          class="px-3 h-9 text-sm rounded-lg border border-n-weak text-n-slate-11"
          @click="voltar"
        >
          {{ t('AGENTS_RODIZIO.POLICY.BACK') }}
        </button>
      </div>
    </header>

    <p v-if="loading" class="text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.POLICY.LOADING') }}
    </p>
    <p v-else-if="loadError" class="text-sm text-n-ruby-11">
      {{ t('AGENTS_RODIZIO.POLICY.ERROR') }}
    </p>
    <p v-else-if="!temTime" class="text-sm text-n-slate-10">
      {{ t('AGENTS_RODIZIO.POLICY.NO_TEAM') }}
    </p>

    <template v-else>
      <p
        v-if="!politicaExiste"
        class="px-4 py-3 text-sm rounded-xl bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11"
      >
        {{ t('AGENTS_RODIZIO.POLICY.EMPTY') }}
      </p>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.ENGINE.TITLE') }}
        </h2>
        <label class="flex gap-2 items-center text-sm text-n-slate-12">
          <input v-model="form.ativo" type="checkbox" />
          {{ t('AGENTS_RODIZIO.POLICY.ENGINE.ACTIVE') }}
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.ENGINE.ACTIVE_HINT') }}
        </p>
        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.ENGINE.MODE') }}
          <select
            v-model="form.modo"
            class="px-2 h-9 max-w-2xl text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          >
            <option v-for="modo in modosDisponiveis" :key="modo" :value="modo">
              {{ rotuloModo(modo) }}
            </option>
          </select>
        </label>
      </section>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.POOL.TITLE') }}
        </h2>
        <p class="max-w-3xl text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.POOL.SUBTITLE') }}
        </p>
        <p v-if="!pool.length" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.POOL.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-1">
          <li
            v-for="(linha, indice) in pool"
            :key="linha.user_id"
            class="flex flex-wrap gap-3 items-center px-3 py-2 rounded-lg border border-n-weak"
          >
            <span class="w-10 text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.POLICY.POOL.POSITION', { n: indice + 1 }) }}
            </span>
            <div class="flex flex-col">
              <button
                class="text-xs text-n-slate-11 disabled:opacity-30"
                :disabled="indice === 0"
                :title="t('AGENTS_RODIZIO.POLICY.POOL.UP')"
                @click="mover(indice, -1)"
              >
                <span class="i-lucide-chevron-up size-4" />
              </button>
              <button
                class="text-xs text-n-slate-11 disabled:opacity-30"
                :disabled="indice === pool.length - 1"
                :title="t('AGENTS_RODIZIO.POLICY.POOL.DOWN')"
                @click="mover(indice, 1)"
              >
                <span class="i-lucide-chevron-down size-4" />
              </button>
            </div>
            <span class="flex-1 min-w-40 text-sm text-n-slate-12">
              {{ linha.name }}
            </span>
            <label class="flex gap-2 items-center text-sm text-n-slate-11">
              <input v-model="linha.ativo" type="checkbox" />
              {{ t('AGENTS_RODIZIO.POLICY.POOL.ON') }}
            </label>
            <label class="flex gap-2 items-center text-sm text-n-slate-11">
              {{ t('AGENTS_RODIZIO.POLICY.POOL.CAP') }}
              <input
                v-model="linha.cap"
                type="number"
                min="1"
                class="px-2 w-20 h-8 text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
              />
            </label>
          </li>
        </ul>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.POOL.CAP_HINT') }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.CONTINUITY.TITLE') }}
        </h2>
        <label class="flex gap-2 items-center text-sm text-n-slate-12">
          <input v-model="form.continuidade_ativa" type="checkbox" />
          {{ t('AGENTS_RODIZIO.POLICY.CONTINUITY.ACTIVE') }}
        </label>
        <label class="flex gap-2 items-center text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.CONTINUITY.DAYS') }}
          <input
            v-model="form.continuidade_dias"
            type="number"
            min="1"
            :disabled="!form.continuidade_ativa"
            class="px-2 w-24 h-8 text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          />
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.CONTINUITY.HINT') }}
        </p>
      </section>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.TITLE') }}
        </h2>
        <label class="flex gap-2 items-center text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.MINUTES') }}
          <input
            v-model="form.sla_assumir_minutos"
            type="number"
            min="1"
            class="px-2 w-24 h-8 text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          />
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.MINUTES_HINT') }}
        </p>
        <label class="flex gap-2 items-center text-sm text-n-slate-12">
          <input v-model="form.repasse_automatico" type="checkbox" />
          {{ t('AGENTS_RODIZIO.POLICY.SLA.AUTO') }}
        </label>
        <label class="flex gap-2 items-center text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.MAX') }}
          <input
            v-model="form.max_repasses"
            type="number"
            min="0"
            :disabled="!form.repasse_automatico"
            class="px-2 w-24 h-8 text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          />
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.MAX_HINT') }}
        </p>
        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.POLICY.SLA.FALLBACK') }}
          <select
            v-model="form.pool_esgotado_destino_user_id"
            class="px-2 h-9 max-w-md text-sm bg-white rounded-lg border dark:bg-n-solid-3 border-n-weak text-n-slate-12"
          >
            <option :value="null">
              {{ t('AGENTS_RODIZIO.POLICY.SLA.FALLBACK_NONE') }}
            </option>
            <option
              v-for="membro in membros"
              :key="membro.id"
              :value="membro.id"
            >
              {{ membro.name || membro.email }}
            </option>
          </select>
        </label>
      </section>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.OWNERSHIP.TITLE') }}
        </h2>
        <label class="flex gap-2 items-start text-sm text-n-slate-12">
          <input v-model="form.modo_posse" type="radio" value="assignee" />
          {{ t('AGENTS_RODIZIO.POLICY.OWNERSHIP.ASSIGNEE') }}
        </label>
        <label class="flex gap-2 items-start text-sm text-n-slate-12">
          <input v-model="form.modo_posse" type="radio" value="designacao" />
          {{ t('AGENTS_RODIZIO.POLICY.OWNERSHIP.DESIGNATION') }}
        </label>
      </section>

      <section
        class="flex flex-col gap-3 p-4 bg-white rounded-xl border dark:bg-n-solid-2 border-n-weak"
      >
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.POLICY.TRIGGER.TITLE') }}
        </h2>
        <label class="flex gap-2 items-center text-sm text-n-slate-12">
          <input v-model="form.gatilho_sem_ia" type="checkbox" />
          {{ t('AGENTS_RODIZIO.POLICY.TRIGGER.ACTIVE') }}
        </label>
        <p class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.TRIGGER.HINT') }}
        </p>
      </section>

      <section
        v-if="erros.length || errosServidor.length"
        class="flex flex-col gap-1 px-4 py-3 rounded-xl border border-n-ruby-8"
      >
        <p class="text-sm font-medium text-n-ruby-11">
          {{ t('AGENTS_RODIZIO.POLICY.ERRORS.TITLE') }}
        </p>
        <p v-for="erro in erros" :key="erro" class="text-sm text-n-ruby-11">
          {{ rotuloErro(erro) }}
        </p>
        <p
          v-for="(erro, indice) in errosServidor"
          :key="indice"
          class="text-sm text-n-ruby-11"
        >
          {{ erro }}
        </p>
      </section>

      <footer class="flex flex-wrap gap-3 items-center">
        <button
          class="px-4 h-9 text-sm text-white rounded-lg transition-shadow bg-n-brand hover:shadow-md disabled:opacity-50"
          :disabled="salvando"
          @click="salvar"
        >
          {{
            salvando
              ? t('AGENTS_RODIZIO.POLICY.SAVING')
              : t('AGENTS_RODIZIO.POLICY.SAVE')
          }}
        </button>
        <template v-if="politicaExiste">
          <button
            v-if="!confirmandoRemocao"
            class="px-3 h-9 text-sm rounded-lg border border-n-weak text-n-ruby-11"
            @click="confirmandoRemocao = true"
          >
            {{ t('AGENTS_RODIZIO.POLICY.REMOVE') }}
          </button>
          <template v-else>
            <button
              class="px-3 h-9 text-sm text-white rounded-lg bg-n-ruby-9 disabled:opacity-50"
              :disabled="salvando"
              @click="remover"
            >
              {{ t('AGENTS_RODIZIO.POLICY.REMOVE_CONFIRM') }}
            </button>
            <button
              class="px-3 h-9 text-sm rounded-lg border border-n-weak text-n-slate-11"
              @click="confirmandoRemocao = false"
            >
              {{ t('AGENTS_RODIZIO.POLICY.REMOVE_CANCEL') }}
            </button>
          </template>
        </template>
        <span class="text-xs text-n-slate-10">
          {{ t('AGENTS_RODIZIO.POLICY.REMOVE_HINT') }}
        </span>
      </footer>
    </template>
  </div>
</template>
