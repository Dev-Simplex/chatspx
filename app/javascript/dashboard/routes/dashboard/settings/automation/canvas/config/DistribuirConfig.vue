<script setup>
// Editor de `distribuir`. O nó NÃO tem parâmetro: o Motor de Distribuição age sempre no time
// ATUAL da conversa, porque é o TIME que carrega a política (Spx::Distribuicao::Policy é por
// time). Um seletor aqui só permitiria mentir — o backend leria o time da conversa do mesmo
// jeito. Então o painel não configura: ele EXPLICA onde a regra mora (Agentes › Rodízio) e
// AVISA quando não há política nenhuma configurada — o caso em que este nó vira `skipped`
// ('sem_politica') em toda execução, silenciosamente, se ninguém contar.
//
// A lista de times COM política ativa sai do endpoint do painel de Rodízio
// (distribuicao_dashboard#show → `times`), o único que já a expõe. Pedimos um período VAZIO
// (de == ate) de propósito: só interessa o `times`, e assim as demais seções do payload voltam
// vazias e a consulta sai barata. A rota do canvas é admin-only (automation.routes.js), a mesma
// exigência do endpoint — o 401 não é um caso que este painel produza.
//
// Falha de rede NÃO vira aviso: afirmar "não há política" sem ter conseguido perguntar seria
// mentir na mesma medida que a guarda muda que este bloco veio corrigir. Nesse caso mostramos
// só a explicação.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import DistribuicaoDashboardAPI from 'dashboard/api/distribuicaoDashboard';

defineOptions({ inheritAttrs: false });

const { t } = useI18n();

const teams = ref([]);
// loading → loaded (sabemos a resposta) → unknown (a consulta falhou; não afirmamos nada)
const status = ref('loading');

const teamNames = computed(() => teams.value.map(team => team.name).join(', '));
const hasPolicies = computed(
  () => status.value === 'loaded' && teams.value.length > 0
);
const missingPolicies = computed(
  () => status.value === 'loaded' && teams.value.length === 0
);

onMounted(async () => {
  try {
    const now = new Date().toISOString();
    const { data } = await DistribuicaoDashboardAPI.show({ de: now, ate: now });
    teams.value = Array.isArray(data?.times) ? data.times : [];
    status.value = 'loaded';
  } catch {
    teams.value = [];
    status.value = 'unknown';
  }
});
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="config-distribuir">
    <div class="flex gap-2 p-3 rounded-md bg-n-alpha-1 text-n-slate-11">
      <span class="mt-0.5 shrink-0 i-lucide-shuffle" />
      <div class="flex flex-col gap-1">
        <p class="text-sm leading-snug">
          {{ t('AUTOMATION.CANVAS.CONFIG.DISTRIBUIR.EXPLANATION') }}
        </p>
        <p class="text-xs leading-snug text-n-slate-10">
          {{ t('AUTOMATION.CANVAS.CONFIG.DISTRIBUIR.HINT') }}
        </p>
      </div>
    </div>

    <div
      v-if="missingPolicies"
      class="flex gap-2 p-3 rounded-md bg-n-amber-3 text-n-amber-11"
      data-testid="config-distribuir-no-policy"
    >
      <span class="mt-0.5 shrink-0 i-lucide-triangle-alert" />
      <p class="text-xs leading-snug">
        {{ t('AUTOMATION.CANVAS.CONFIG.DISTRIBUIR.NO_POLICY') }}
      </p>
    </div>

    <p v-else-if="hasPolicies" class="text-xs leading-snug text-n-slate-10">
      {{
        t('AUTOMATION.CANVAS.CONFIG.DISTRIBUIR.TEAMS_WITH_POLICY', {
          teams: teamNames,
        })
      }}
    </p>
  </div>
</template>
