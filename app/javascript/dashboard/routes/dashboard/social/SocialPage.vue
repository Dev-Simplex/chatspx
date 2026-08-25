<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import socialComentariosAPI from 'dashboard/api/socialComentarios';
import socialPublicacoesAPI from 'dashboard/api/socialPublicacoes';

const { t } = useI18n();

// Fase 1 da SPEC: ver o que chegou. Responder é a fatia seguinte, e as abas de campanha,
// marcações, agenda e painel vêm depois — ver docs/SPEC-instagram-social.md §6.
const ABAS = ['comentarios', 'publicacoes'];
const abaAtiva = ref('comentarios');

const comentarios = ref([]);
const publicacoes = ref([]);
const carregando = ref(false);

const publicacaoId = ref('');
const incluirProprios = ref(false);
const soNaoRespondidos = ref(false);

const carregarComentarios = async () => {
  const { data } = await socialComentariosAPI.getAll({
    publicacaoId: publicacaoId.value || undefined,
    incluirProprios: incluirProprios.value || undefined,
  });
  comentarios.value = data || [];
};

const carregar = async () => {
  carregando.value = true;
  try {
    const [, respostaPublicacoes] = await Promise.all([
      carregarComentarios(),
      socialPublicacoesAPI.getAll(),
    ]);
    publicacoes.value = respostaPublicacoes.data || [];
  } catch (error) {
    useAlert(t('REDE_SOCIAL.ERRO_CARREGAR'));
  } finally {
    carregando.value = false;
  }
};

const refiltrar = async () => {
  carregando.value = true;
  try {
    await carregarComentarios();
  } catch (error) {
    useAlert(t('REDE_SOCIAL.ERRO_CARREGAR'));
  } finally {
    carregando.value = false;
  }
};

// O filtro de "não respondidos" fica no cliente de propósito: ele opera sobre a mesma página
// que veio do servidor, então o operador vê quantos dos que estão na tela ainda faltam, sem
// que a contagem mude debaixo dele a cada clique.
const comentariosVisiveis = computed(() =>
  soNaoRespondidos.value
    ? comentarios.value.filter(comentario => !comentario.respondido)
    : comentarios.value
);

const naoRespondidos = computed(
  () => comentarios.value.filter(comentario => !comentario.respondido).length
);

const legendaCurta = publicacao => {
  const legenda = publicacao?.legenda || '';
  return legenda.length > 80 ? `${legenda.slice(0, 80)}…` : legenda;
};

const formatarData = valor => (valor ? new Date(valor).toLocaleString() : '');

onMounted(carregar);
</script>

<template>
  <div class="flex-1 overflow-auto bg-n-solid-1">
    <div class="max-w-6xl px-6 py-8 mx-auto">
      <h1 class="mb-1 text-2xl font-semibold text-n-slate-12">
        {{ $t('REDE_SOCIAL.TITULO') }}
      </h1>
      <p class="mb-6 text-sm text-n-slate-11">
        {{ $t('REDE_SOCIAL.DESCRICAO') }}
      </p>

      <div class="flex gap-1 mb-6 border-b border-n-weak">
        <button
          v-for="aba in ABAS"
          :key="aba"
          class="px-4 py-2 -mb-px text-sm font-medium transition-colors border-b-2"
          :class="
            abaAtiva === aba
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="abaAtiva = aba"
        >
          {{ $t(`REDE_SOCIAL.ABAS.${aba.toUpperCase()}`) }}
        </button>
      </div>

      <!-- Aba Comentários -->
      <div v-if="abaAtiva === 'comentarios'">
        <div class="flex flex-wrap items-end gap-3 mb-4">
          <label class="text-sm">
            <span class="block mb-1 text-n-slate-11">
              {{ $t('REDE_SOCIAL.FILTRO_PUBLICACAO') }}
            </span>
            <select
              v-model="publicacaoId"
              class="px-3 py-2 border rounded bg-n-solid-1 border-n-weak text-n-slate-12"
              @change="refiltrar"
            >
              <option value="">{{ $t('REDE_SOCIAL.TODAS_PUBLICACOES') }}</option>
              <option
                v-for="publicacao in publicacoes"
                :key="publicacao.id"
                :value="publicacao.id"
              >
                {{ legendaCurta(publicacao) || publicacao.external_id }}
              </option>
            </select>
          </label>

          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input
              v-model="soNaoRespondidos"
              type="checkbox"
              class="rounded border-n-weak"
            />
            {{ $t('REDE_SOCIAL.SO_NAO_RESPONDIDOS', { total: naoRespondidos }) }}
          </label>

          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input
              v-model="incluirProprios"
              type="checkbox"
              class="rounded border-n-weak"
              @change="refiltrar"
            />
            {{ $t('REDE_SOCIAL.INCLUIR_PROPRIOS') }}
          </label>
        </div>

        <p v-if="carregando" class="text-sm text-n-slate-11">
          {{ $t('REDE_SOCIAL.CARREGANDO') }}
        </p>
        <p v-else-if="!comentariosVisiveis.length" class="text-sm text-n-slate-11">
          {{ $t('REDE_SOCIAL.SEM_COMENTARIOS') }}
        </p>
        <div
          v-for="comentario in comentariosVisiveis"
          v-else
          :key="comentario.id"
          class="flex gap-3 p-3 mb-2 bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak"
        >
          <img
            v-if="comentario.publicacao?.thumbnail_url"
            :src="comentario.publicacao.thumbnail_url"
            :alt="legendaCurta(comentario.publicacao)"
            class="object-cover rounded size-12 shrink-0"
          />
          <div class="min-w-0">
            <div class="flex flex-wrap items-baseline gap-2 text-sm">
              <span class="font-medium text-n-slate-12">
                @{{ comentario.autor_username || $t('REDE_SOCIAL.AUTOR_DESCONHECIDO') }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ formatarData(comentario.comentado_em) }}
              </span>
              <span
                v-if="comentario.proprio"
                class="px-2 py-0.5 text-xs rounded bg-n-solid-3 text-n-slate-11"
              >
                {{ $t('REDE_SOCIAL.RESPOSTA_DA_CONTA') }}
              </span>
              <span
                v-else-if="comentario.respondido"
                class="px-2 py-0.5 text-xs rounded bg-n-solid-3 text-n-slate-11"
                :title="$t('REDE_SOCIAL.RESPONDIDO_AJUDA')"
              >
                {{ $t('REDE_SOCIAL.RESPONDIDO') }}
              </span>
            </div>
            <p class="text-sm break-words text-n-slate-12">{{ comentario.texto }}</p>
            <a
              v-if="comentario.publicacao?.permalink"
              :href="comentario.publicacao.permalink"
              target="_blank"
              rel="noopener noreferrer"
              class="text-xs text-n-slate-10 hover:underline"
            >
              {{ legendaCurta(comentario.publicacao) || $t('REDE_SOCIAL.VER_PUBLICACAO') }}
            </a>
          </div>
        </div>
      </div>

      <!-- Aba Publicações -->
      <div v-else>
        <p v-if="carregando" class="text-sm text-n-slate-11">
          {{ $t('REDE_SOCIAL.CARREGANDO') }}
        </p>
        <p v-else-if="!publicacoes.length" class="text-sm text-n-slate-11">
          {{ $t('REDE_SOCIAL.SEM_PUBLICACOES') }}
        </p>
        <div
          v-for="publicacao in publicacoes"
          v-else
          :key="publicacao.id"
          class="flex gap-3 p-3 mb-2 bg-white border rounded-lg dark:bg-n-solid-2 border-n-weak"
        >
          <img
            v-if="publicacao.thumbnail_url"
            :src="publicacao.thumbnail_url"
            :alt="legendaCurta(publicacao)"
            class="object-cover rounded size-16 shrink-0"
          />
          <div class="min-w-0">
            <div class="flex flex-wrap items-baseline gap-2 text-sm">
              <span class="font-medium text-n-slate-12">
                {{ publicacao.tipo || $t('REDE_SOCIAL.TIPO_DESCONHECIDO') }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ formatarData(publicacao.publicada_em) }}
              </span>
              <!-- Publicação que só o webhook alimentou: ninguém falou com a Graph ainda, então
                   legenda e miniatura estão vazias. É estado normal, não erro. -->
              <span
                v-if="!publicacao.sincronizada"
                class="px-2 py-0.5 text-xs rounded bg-n-solid-3 text-n-slate-11"
              >
                {{ $t('REDE_SOCIAL.NAO_SINCRONIZADA') }}
              </span>
            </div>
            <p class="text-sm break-words text-n-slate-11">
              {{ legendaCurta(publicacao) }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{
                $t('REDE_SOCIAL.CONTAGEM', {
                  clientes: publicacao.comentarios_de_terceiros,
                  respostas: publicacao.respostas_da_conta,
                })
              }}
              <template v-if="publicacao.metricas?.comments_count">
                · {{ $t('REDE_SOCIAL.NO_INSTAGRAM', { total: publicacao.metricas.comments_count }) }}
              </template>
            </p>
            <a
              v-if="publicacao.permalink"
              :href="publicacao.permalink"
              target="_blank"
              rel="noopener noreferrer"
              class="text-xs text-n-slate-10 hover:underline"
            >
              {{ $t('REDE_SOCIAL.VER_PUBLICACAO') }}
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
