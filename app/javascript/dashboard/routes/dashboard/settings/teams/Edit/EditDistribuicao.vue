<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TeamDistribuicaoAPI from 'dashboard/api/teamDistribuicao';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PageHeader from '../../SettingsSubPageHeader.vue';

const route = useRoute();
const { t } = useI18n();

const teamId = computed(() => route.params.teamId);

const carregando = ref(true);
const salvando = ref(false);
const semPermissao = ref(false);
const politica = ref({});
const pool = ref([]);
const candidatos = ref([]);
const nomeTime = ref('');
// Linha do pool cujo formulário de suspensão está aberto (user_id), ou null.
const suspendendo = ref(null);
const suspensaoAte = ref('');
const suspensaoMotivo = ref('');

const cabecalho = computed(() =>
  nomeTime.value
    ? `${t('TEAMS_SETTINGS.DISTRIBUICAO.TITLE')} — ${nomeTime.value}`
    : t('TEAMS_SETTINGS.DISTRIBUICAO.TITLE')
);

// Só faz sentido oferecer o resto quando a distribuição está ligada. Desligada, a tela
// continua mostrando o pool (é informação útil) mas sem prometer que ele age.
const ligada = computed(() => politica.value.ativo);

function aplicar(dados) {
  politica.value = { ...dados.politica };
  pool.value = [...dados.pool];
  candidatos.value = [...dados.candidatos];
  nomeTime.value = dados.time?.nome || '';
}

async function carregar() {
  carregando.value = true;
  try {
    const { data } = await TeamDistribuicaoAPI.show(teamId.value);
    aplicar(data);
  } catch (erro) {
    if (erro.response?.status === 401) semPermissao.value = true;
    else useAlert(t('TEAMS_SETTINGS.DISTRIBUICAO.ERROR'));
  }
  carregando.value = false;
}

onMounted(carregar);

// A ordem da lista É a ordem do rodízio — por isso mover é uma ação de primeira classe,
// e não um detalhe visual.
function mover(indice, passo) {
  const destino = indice + passo;
  if (destino < 0 || destino >= pool.value.length) return;
  const copia = [...pool.value];
  [copia[indice], copia[destino]] = [copia[destino], copia[indice]];
  pool.value = copia;
}

function adicionar(candidato) {
  pool.value = [
    ...pool.value,
    {
      user_id: candidato.user_id,
      nome: candidato.nome,
      ativo: true,
      suspenso_ate: null,
      motivo: null,
      cap: null,
      produtos: [],
      estado: 'ativo',
      membro_do_time: true,
    },
  ];
  candidatos.value = candidatos.value.filter(
    c => c.user_id !== candidato.user_id
  );
}

function remover(entrada) {
  pool.value = pool.value.filter(e => e.user_id !== entrada.user_id);
  if (entrada.membro_do_time) {
    candidatos.value = [
      ...candidatos.value,
      { user_id: entrada.user_id, nome: entrada.nome },
    ];
  }
}

function abrirSuspensao(entrada) {
  suspendendo.value = entrada.user_id;
  suspensaoAte.value = entrada.suspenso_ate || '';
  suspensaoMotivo.value = entrada.motivo || '';
}

function atualizar(entrada, mudancas) {
  pool.value = pool.value.map(e =>
    e.user_id === entrada.user_id ? { ...e, ...mudancas } : e
  );
}

function confirmarSuspensao(entrada) {
  atualizar(entrada, {
    ativo: true,
    suspenso_ate: suspensaoAte.value || null,
    motivo: suspensaoMotivo.value || null,
    // Sem data é suspensão sem fim — que é exatamente "desligado".
    estado: suspensaoAte.value ? 'suspenso' : 'ativo',
  });
  suspendendo.value = null;
}

function desligar(entrada) {
  atualizar(entrada, { ativo: false, estado: 'desativado' });
}

function reativar(entrada) {
  atualizar(entrada, {
    ativo: true,
    suspenso_ate: null,
    motivo: null,
    estado: 'ativo',
  });
}

async function salvar() {
  salvando.value = true;
  try {
    const { data } = await TeamDistribuicaoAPI.update(teamId.value, {
      ...politica.value,
      pool: pool.value.map(e => ({
        user_id: e.user_id,
        ativo: e.ativo,
        suspenso_ate: e.suspenso_ate,
        motivo: e.motivo,
        cap: e.cap,
        produtos: e.produtos,
      })),
    });
    aplicar(data);
    useAlert(t('TEAMS_SETTINGS.DISTRIBUICAO.SAVED'));
  } catch (erro) {
    const motivo =
      erro.response?.status === 401
        ? t('TEAMS_SETTINGS.DISTRIBUICAO.FORBIDDEN')
        : t('TEAMS_SETTINGS.DISTRIBUICAO.ERROR');
    useAlert(motivo);
  }
  salvando.value = false;
}
</script>

<template>
  <div class="h-full w-full p-8 col-span-6 overflow-auto">
    <div v-if="carregando" class="flex items-center justify-center py-6">
      <Spinner class="text-n-blue-11" />
    </div>

    <p v-else-if="semPermissao" class="text-sm text-n-ruby-11">
      {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.FORBIDDEN') }}
    </p>

    <form v-else class="flex flex-col gap-6 mx-0" @submit.prevent="salvar">
      <PageHeader
        :header-title="cabecalho"
        :header-content="$t('TEAMS_SETTINGS.DISTRIBUICAO.DESC')"
      />

      <label class="flex items-start gap-2">
        <input v-model="politica.ativo" type="checkbox" class="mt-1" />
        <span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.ENABLE') }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.ENABLE_HELP') }}
          </span>
        </span>
      </label>

      <p class="text-xs text-n-slate-11 border-l-2 border-n-weak pl-3">
        {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.CASCATA') }}
      </p>

      <fieldset :disabled="!ligada" class="flex flex-col gap-6">
        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.MODO.LABEL') }}
          </span>
          <select
            v-model="politica.modo"
            class="max-w-md rounded-lg border border-n-weak bg-n-solid-1 text-sm"
          >
            <option value="rodizio">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.MODO.RODIZIO') }}
            </option>
            <option value="online">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.MODO.ONLINE') }}
            </option>
            <option value="off">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.MODO.OFF') }}
            </option>
          </select>
        </div>

        <div class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POSSE.LABEL') }}
          </span>
          <select
            v-model="politica.modo_posse"
            class="max-w-md rounded-lg border border-n-weak bg-n-solid-1 text-sm"
          >
            <option value="assignee">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POSSE.ASSIGNEE') }}
            </option>
            <option value="designacao">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POSSE.DESIGNACAO') }}
            </option>
          </select>
        </div>

        <div class="flex flex-col gap-1">
          <label class="flex items-center gap-2">
            <input v-model="politica.continuidade_ativa" type="checkbox" />
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.CONTINUIDADE.LABEL') }}
            </span>
          </label>
          <div class="flex items-center gap-2 pl-6">
            <input
              v-model.number="politica.continuidade_dias"
              type="number"
              min="1"
              class="w-20 rounded-lg border border-n-weak bg-n-solid-1 text-sm"
            />
            <span class="text-xs text-n-slate-11">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.CONTINUIDADE.DAYS') }}
            </span>
          </div>
          <p class="text-xs text-n-slate-11 pl-6">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.CONTINUIDADE.HELP') }}
          </p>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.LABEL') }}
            </span>
            <input
              v-model.number="politica.sla_assumir_minutos"
              type="number"
              min="1"
              class="w-20 rounded-lg border border-n-weak bg-n-solid-1 text-sm"
            />
            <span class="text-xs text-n-slate-11">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.MINUTES') }}
            </span>
          </div>

          <div class="flex flex-col gap-2 pl-6">
            <span class="text-xs text-n-slate-11">
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.ON_EXPIRY') }}
            </span>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="politica.repasse_automatico"
                type="radio"
                :value="true"
              />
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.REPASSE') }}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="politica.repasse_automatico"
                type="radio"
                :value="false"
              />
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.ALERT') }}
            </label>

            <div
              v-if="politica.repasse_automatico"
              class="flex flex-col gap-2 pl-6"
            >
              <div class="flex items-center gap-2">
                <span class="text-xs text-n-slate-11">
                  {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.MAX') }}
                </span>
                <input
                  v-model.number="politica.max_repasses"
                  type="number"
                  min="1"
                  class="w-16 rounded-lg border border-n-weak bg-n-solid-1 text-sm"
                />
              </div>
              <div class="flex items-center gap-2">
                <span class="text-xs text-n-slate-11">
                  {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.DESTINO') }}
                </span>
                <select
                  v-model="politica.pool_esgotado_destino_user_id"
                  class="max-w-xs rounded-lg border border-n-weak bg-n-solid-1 text-sm"
                >
                  <option :value="null">
                    {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.DESTINO_NONE') }}
                  </option>
                  <option
                    v-for="pessoa in pool"
                    :key="pessoa.user_id"
                    :value="pessoa.user_id"
                  >
                    {{ pessoa.nome }}
                  </option>
                </select>
              </div>
            </div>

            <label class="flex items-center gap-2 text-sm">
              <input v-model="politica.sla_respeita_horario" type="checkbox" />
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.HORARIO') }}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="politica.expirado_conta_como_recebido"
                type="checkbox"
              />
              {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.SLA.EXPIRADO') }}
            </label>
          </div>
        </div>
      </fieldset>

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.TITLE') }}
        </span>
        <p class="text-xs text-n-slate-11">
          {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.ORDER_HELP') }}
        </p>

        <p v-if="!pool.length" class="text-sm text-n-slate-11 py-2">
          {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.EMPTY') }}
        </p>

        <ul
          v-else
          class="flex flex-col divide-y divide-n-weak rounded-lg border border-n-weak"
        >
          <li
            v-for="(entrada, indice) in pool"
            :key="entrada.user_id"
            class="flex flex-col gap-2 p-3"
          >
            <div class="flex items-center gap-3 flex-wrap">
              <span class="text-xs text-n-slate-10 w-6">{{ indice + 1 }}</span>
              <span class="text-sm text-n-slate-12 flex-1">
                {{ entrada.nome }}
              </span>

              <span
                v-if="entrada.estado === 'ativo'"
                class="text-xs text-n-teal-11"
              >
                {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.ATIVO') }}
              </span>
              <span
                v-else-if="entrada.estado === 'suspenso'"
                class="text-xs text-n-amber-11"
              >
                {{
                  $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.SUSPENSO', {
                    date: entrada.suspenso_ate,
                  })
                }}
              </span>
              <span v-else class="text-xs text-n-slate-10">
                {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.DESATIVADO') }}
              </span>

              <span
                v-if="!entrada.membro_do_time"
                class="text-xs text-n-ruby-11"
              >
                {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.NOT_MEMBER') }}
              </span>

              <div class="flex items-center gap-1">
                <NextButton
                  type="button"
                  ghost
                  slate
                  size="xs"
                  icon="i-lucide-chevron-up"
                  :title="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.UP')"
                  @click="mover(indice, -1)"
                />
                <NextButton
                  type="button"
                  ghost
                  slate
                  size="xs"
                  icon="i-lucide-chevron-down"
                  :title="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.DOWN')"
                  @click="mover(indice, 1)"
                />
                <NextButton
                  v-if="entrada.estado === 'ativo'"
                  type="button"
                  ghost
                  slate
                  size="xs"
                  :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.SUSPEND')"
                  @click="abrirSuspensao(entrada)"
                />
                <NextButton
                  v-else
                  type="button"
                  ghost
                  blue
                  size="xs"
                  :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.REACTIVATE')"
                  @click="reativar(entrada)"
                />
                <NextButton
                  v-if="entrada.ativo"
                  type="button"
                  ghost
                  slate
                  size="xs"
                  :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.DISABLE')"
                  @click="desligar(entrada)"
                />
                <NextButton
                  type="button"
                  ghost
                  ruby
                  size="xs"
                  :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.REMOVE')"
                  @click="remover(entrada)"
                />
              </div>
            </div>

            <div
              v-if="suspendendo === entrada.user_id"
              class="flex items-end gap-2 flex-wrap pl-9"
            >
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">
                  {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.UNTIL') }}
                </span>
                <input
                  v-model="suspensaoAte"
                  type="date"
                  class="rounded-lg border border-n-weak bg-n-solid-1 text-sm"
                />
              </label>
              <label class="flex flex-col gap-1 flex-1 min-w-40">
                <span class="text-xs text-n-slate-11">
                  {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.REASON') }}
                </span>
                <input
                  v-model="suspensaoMotivo"
                  type="text"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm"
                />
              </label>
              <NextButton
                type="button"
                blue
                size="xs"
                :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.SUSPEND')"
                @click="confirmarSuspensao(entrada)"
              />
            </div>
          </li>
        </ul>

        <div
          v-if="candidatos.length"
          class="flex items-center gap-2 flex-wrap pt-2"
        >
          <span class="text-xs text-n-slate-11">
            {{ $t('TEAMS_SETTINGS.DISTRIBUICAO.POOL.ADD') }}
          </span>
          <NextButton
            v-for="candidato in candidatos"
            :key="candidato.user_id"
            type="button"
            faded
            blue
            size="xs"
            icon="i-lucide-user-plus"
            :label="candidato.nome"
            @click="adicionar(candidato)"
          />
        </div>
      </div>

      <div>
        <NextButton
          type="submit"
          :label="$t('TEAMS_SETTINGS.DISTRIBUICAO.SAVE')"
          :is-loading="salvando"
        />
      </div>
    </form>
  </div>
</template>
