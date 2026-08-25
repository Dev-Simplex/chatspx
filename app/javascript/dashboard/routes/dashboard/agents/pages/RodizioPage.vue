<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';

defineOptions({ name: 'RodizioPage' });

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const loading = ref(true);
const loadError = ref(false);
const data = ref(null);
const teamId = ref('');
const detalhe = ref(null);
const detalheLoading = ref(false);

const carregar = async () => {
  loading.value = true;
  loadError.value = false;
  detalhe.value = null;
  try {
    const params = teamId.value ? { team_id: teamId.value } : {};
    const { data: payload } = await DistribuicaoDashboardAPI.show(params);
    data.value = payload;
  } catch (e) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(carregar);

const linhas = computed(() => data.value?.linhas || []);
const totais = computed(() => data.value?.totais || {});
const times = computed(() => data.value?.times || []);
const parados = computed(
  () => data.value?.sem_movimento || { total: 0, leads: [], limiar_minutos: 0 }
);

const motivo = (linha, chave) => linha.motivos?.[chave] || 0;

// "WhatsApp 12 · Site 3" — os canais que a gestão já lê na planilha manual.
const canais = linha =>
  Object.entries(linha.canais || {})
    .map(([nome, total]) => `${nome} ${total}`)
    .join(' · ');

const produtos = linha =>
  Object.entries(linha.produtos || {})
    .map(([nome, total]) => `${nome} ${total}`)
    .join(' · ');

const abrirDetalhe = async lead => {
  detalhe.value = { lead, designacoes: [] };
  detalheLoading.value = true;
  try {
    const { data: payload } = await DistribuicaoDashboardAPI.designacoes(
      lead.conversation_id
    );
    detalhe.value = { lead, designacoes: payload.designacoes || [] };
  } catch (e) {
    detalhe.value = { lead, designacoes: [] };
  } finally {
    detalheLoading.value = false;
  }
};

const data_hora = valor => (valor ? new Date(valor).toLocaleString() : '—');

// Montados aqui, e não no template, porque texto solto em template (o "#" e os "·")
// é erro de lint no projeto — nada de string crua fora do i18n.
const conversa = displayId => `#${displayId}`;

const resumoDesignacao = registro =>
  [registro.corretor || '—', registro.motivo, registro.status || '—'].join(' · ');

// Este painel só CONTA o que já aconteceu; quem monta a política é a tela irmã.
const irParaPolitica = () =>
  router.push({
    name: 'agents_rodizio_politica',
    params: { accountId: accountId.value },
  });
</script>

<template>
  <div class="flex flex-col gap-6 p-6 overflow-y-auto">
    <header class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <select
          v-model="teamId"
          class="h-9 px-2 text-sm bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak text-n-slate-12"
          @change="carregar"
        >
          <option value="">{{ t('AGENTS_RODIZIO.ALL_TEAMS') }}</option>
          <option v-for="time in times" :key="time.id" :value="time.id">
            {{ time.name }} ({{ time.modo_posse }})
          </option>
        </select>
        <button
          class="h-9 px-3 text-sm rounded-lg bg-n-brand text-white transition-shadow hover:shadow-md"
          @click="carregar"
        >
          {{ t('AGENTS_RODIZIO.RELOAD') }}
        </button>
        <button
          class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11"
          @click="irParaPolitica"
        >
          {{ t('AGENTS_RODIZIO.CONFIGURE') }}
        </button>
      </div>
    </header>

    <p v-if="loading" class="text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.LOADING') }}
    </p>
    <p v-else-if="loadError" class="text-sm text-n-ruby-11">
      {{ t('AGENTS_RODIZIO.ERROR') }}
    </p>

    <template v-else>
      <section class="flex flex-wrap gap-4">
        <div class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak">
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.TOTAL_RECEIVED') }}
          </p>
          <p class="text-2xl font-medium text-n-slate-12">
            {{ totais.recebidos || 0 }}
          </p>
        </div>
        <div class="px-4 py-3 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak">
          <p class="text-xs uppercase text-n-slate-10">
            {{ t('AGENTS_RODIZIO.STALLED.TITLE') }}
          </p>
          <p class="text-2xl font-medium text-n-slate-12">{{ parados.total }}</p>
          <p class="text-xs text-n-slate-10">
            {{ t('AGENTS_RODIZIO.STALLED.THRESHOLD', { min: parados.limiar_minutos }) }}
          </p>
        </div>
      </section>

      <section class="overflow-x-auto">
        <table class="w-full text-sm border rounded-xl border-n-weak">
          <thead class="bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11">
            <tr>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.CONSULTANT') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.RECEIVED') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.ROTATION') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.CONTINUITY') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.PREFERENCE') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.MANUAL') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('AGENTS_RODIZIO.TABLE.OPEN') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.CHANNELS') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('AGENTS_RODIZIO.TABLE.PRODUCTS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!linhas.length">
              <td colspan="9" class="px-3 py-6 text-center text-n-slate-10">
                {{ t('AGENTS_RODIZIO.EMPTY') }}
              </td>
            </tr>
            <tr
              v-for="linha in linhas"
              :key="linha.user_id"
              class="border-t border-n-weak"
            >
              <td class="px-3 py-2 text-n-slate-12">{{ linha.nome || linha.user_id }}</td>
              <td class="px-3 py-2 text-right text-n-slate-12">{{ linha.recebidos }}</td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ motivo(linha, 'rodizio') }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ motivo(linha, 'continuidade') }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ motivo(linha, 'preferencia_cliente') }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ motivo(linha, 'manual_gestor') }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">{{ linha.abertos }}</td>
              <td class="px-3 py-2 text-n-slate-10">{{ canais(linha) }}</td>
              <td class="px-3 py-2 text-n-slate-10">{{ produtos(linha) }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="flex flex-col gap-2">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('AGENTS_RODIZIO.STALLED.LIST_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('AGENTS_RODIZIO.STALLED.SUBTITLE') }}
        </p>
        <p v-if="!parados.leads.length" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.STALLED.NONE') }}
        </p>
        <ul v-else class="flex flex-col gap-1">
          <li
            v-for="lead in parados.leads"
            :key="lead.conversation_id"
            class="flex flex-wrap items-center gap-3 px-3 py-2 bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak"
          >
            <span class="text-sm text-n-slate-12">
              {{ conversa(lead.display_id) }}
            </span>
            <span class="text-sm text-n-slate-11">{{ lead.corretor || '—' }}</span>
            <span class="text-sm text-n-slate-10">
              {{ t('AGENTS_RODIZIO.STALLED.MINUTES', { min: lead.minutos_parado }) }}
            </span>
            <span v-if="lead.produto" class="text-xs text-n-slate-10">
              {{ lead.produto }}
            </span>
            <button
              class="ml-auto text-sm underline text-n-slate-11"
              @click="abrirDetalhe(lead)"
            >
              {{ t('AGENTS_RODIZIO.DETAIL.OPEN') }}
            </button>
          </li>
        </ul>
      </section>

      <section
        v-if="detalhe"
        class="flex flex-col gap-2 p-4 bg-white border rounded-xl dark:bg-n-solid-2 border-n-weak"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('AGENTS_RODIZIO.DETAIL.TITLE', { id: detalhe.lead.display_id }) }}
          </h2>
          <button class="text-sm text-n-slate-11" @click="detalhe = null">
            {{ t('AGENTS_RODIZIO.DETAIL.CLOSE') }}
          </button>
        </div>
        <p v-if="detalheLoading" class="text-sm text-n-slate-10">
          {{ t('AGENTS_RODIZIO.LOADING') }}
        </p>
        <!-- wrapper por causa do v-else: v-else e v-for no MESMO elemento é
             anti-padrão do Vue e dá bug de renderização -->
        <div v-else class="flex flex-col gap-3">
          <div
            v-for="registro in detalhe.designacoes"
            :key="registro.id"
            class="flex flex-col gap-1 pt-2 border-t border-n-weak"
          >
            <p class="text-sm text-n-slate-12">
              {{ resumoDesignacao(registro) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.DETAIL.DESIGNATED_AT') }}
              {{ data_hora(registro.designado_em) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('AGENTS_RODIZIO.DETAIL.CANDIDATES') }}
              {{ (registro.candidatos || []).join(', ') || '—' }}
            </p>
            <pre
              class="p-2 overflow-x-auto text-xs rounded-lg bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-11"
              >{{ registro.regra_aplicada }}</pre
            >
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
