<script setup>
// Editor do nó `router` (multi-rota, first-match). Persiste em:
//   node.routes = [{ key, label, conditions }]  // ORDENADO — a 1ª rota que casa vence
//   node.fallback_key = 'fallback'              // ramo "senão", quando nenhuma rota casa
// Cada rota tem um `key` ESTÁVEL (route_N) que é o id do source-handle no FlowNode e o
// `branch` da aresta que sai dela — por isso o key nunca muda ao editar/reordenar (senão as
// arestas quebrariam). As `conditions` são persistidas na forma GERADA (idêntica ao
// ConditionConfig, via conditionHelpers) para o Flows::RunnerService avaliar. Reusa o
// ConditionRow e o mesmo filterTypes (composable useFlowFilterTypes).
import { ref, nextTick, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { getDefaultConditions } from 'dashboard/helper/automationHelper';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ConfigField from './ConfigField.vue';
import { toGeneratedConditions, toRichConditions } from './conditionHelpers';
import { useFlowFilterTypes, EVENT_CONTEXT } from './useFlowFilterTypes';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const { filterTypes, manifestCustomAttributes } = useFlowFilterTypes();

const routes = ref([]);
const fallbackKey = ref('fallback');
// Trava a emissão durante a (re)hidratação a partir do nó, evitando eco de update.
let isHydrating = false;

// Próximo key estável route_N: max(N existentes) + 1. Nunca reusa um número já usado nesta
// sessão de edição, mesmo após remoções, para não colidir com uma aresta órfã ainda no grafo.
const nextRouteKey = () => {
  const used = routes.value
    .map(r => parseInt(String(r.key).replace(/\D/g, ''), 10) || 0)
    .concat(0);
  return `route_${Math.max(...used) + 1}`;
};

const makeRoute = () => ({
  key: nextRouteKey(),
  label: '',
  conditions: getDefaultConditions(EVENT_CONTEXT),
});

const hydrateFromNode = () => {
  isHydrating = true;
  const stored = Array.isArray(props.node.routes) ? props.node.routes : [];
  routes.value = stored.map(route => ({
    key: String(route.key || ''),
    label: route.label || '',
    conditions:
      Array.isArray(route.conditions) && route.conditions.length
        ? toRichConditions(route.conditions, filterTypes.value)
        : getDefaultConditions(EVENT_CONTEXT),
  }));
  // Garante ao menos uma rota e keys válidos (nó recém-criado ou definição legada).
  routes.value = routes.value.map(route =>
    route.key ? route : { ...route, key: nextRouteKey() }
  );
  if (!routes.value.length) routes.value = [makeRoute()];
  fallbackKey.value = props.node.fallback_key || 'fallback';
  nextTick(() => {
    isHydrating = false;
  });
};

const addRoute = () => {
  routes.value = [...routes.value, makeRoute()];
};

const removeRoute = index => {
  routes.value = routes.value.filter((_, i) => i !== index);
};

// Reordena a rota (muda a PRIORIDADE first-match; os keys/arestas ficam intactos).
const moveRoute = (index, delta) => {
  const target = index + delta;
  if (target < 0 || target >= routes.value.length) return;
  const next = [...routes.value];
  [next[index], next[target]] = [next[target], next[index]];
  routes.value = next;
};

const addCondition = routeIndex => {
  routes.value = routes.value.map((route, i) =>
    i === routeIndex
      ? {
          ...route,
          conditions: [
            ...route.conditions,
            ...getDefaultConditions(EVENT_CONTEXT),
          ],
        }
      : route
  );
};

const removeCondition = (routeIndex, condIndex) => {
  routes.value = routes.value.map((route, i) =>
    i === routeIndex
      ? {
          ...route,
          conditions: route.conditions.filter((_, ci) => ci !== condIndex),
        }
      : route
  );
};

onMounted(() => {
  manifestCustomAttributes();
  hydrateFromNode();
});

// Troca de nó selecionado: re-hidrata a partir do novo nó.
watch(
  () => props.node.id,
  () => hydrateFromNode()
);

// Qualquer edição → persiste routes (forma gerada das condições) + fallback_key no nó.
watch(
  routes,
  value => {
    if (isHydrating) return;
    emit('update', {
      routes: value.map(route => ({
        key: route.key,
        label: (route.label || '').trim(),
        conditions: toGeneratedConditions(route.conditions),
      })),
      fallback_key: fallbackKey.value,
    });
  },
  { deep: true }
);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-router">
    <p class="text-xs leading-snug text-n-slate-10">
      {{ t('AUTOMATION.CANVAS.CONFIG.ROUTER.HINT') }}
    </p>

    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="(route, ri) in routes"
        :key="route.key"
        class="flex flex-col gap-2.5 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
        :data-testid="`router-route-${route.key}`"
      >
        <div class="flex items-center gap-1.5">
          <span
            class="text-[10px] font-bold tracking-wider uppercase text-n-slate-10 shrink-0"
          >
            {{ t('AUTOMATION.CANVAS.CONFIG.ROUTER.ROUTE_N', { n: ri + 1 }) }}
          </span>
          <Input
            v-model="route.label"
            size="sm"
            class="flex-1"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.ROUTER.ROUTE_NAME_PLACEHOLDER')
            "
          />
          <NextButton
            icon="i-lucide-chevron-up"
            ghost
            slate
            xs
            :disabled="ri === 0"
            :aria-label="t('AUTOMATION.CANVAS.CONFIG.ROUTER.MOVE_UP')"
            @click="moveRoute(ri, -1)"
          />
          <NextButton
            icon="i-lucide-chevron-down"
            ghost
            slate
            xs
            :disabled="ri === routes.length - 1"
            :aria-label="t('AUTOMATION.CANVAS.CONFIG.ROUTER.MOVE_DOWN')"
            @click="moveRoute(ri, 1)"
          />
          <NextButton
            icon="i-lucide-trash"
            ghost
            ruby
            xs
            :aria-label="t('AUTOMATION.CANVAS.CONFIG.ROUTER.REMOVE_ROUTE')"
            @click="removeRoute(ri)"
          />
        </div>

        <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CONDITION.LABEL')">
          <ul class="flex flex-col gap-2 p-0 m-0 list-none">
            <template v-for="(condition, ci) in route.conditions" :key="ci">
              <ConditionRow
                v-if="ci === 0"
                v-model:attribute-key="route.conditions[ci].attribute_key"
                v-model:filter-operator="route.conditions[ci].filter_operator"
                v-model:values="route.conditions[ci].values"
                :filter-types="filterTypes"
                :show-query-operator="false"
                @remove="removeCondition(ri, ci)"
              />
              <ConditionRow
                v-else
                v-model:attribute-key="route.conditions[ci].attribute_key"
                v-model:filter-operator="route.conditions[ci].filter_operator"
                v-model:query-operator="route.conditions[ci - 1].query_operator"
                v-model:values="route.conditions[ci].values"
                :filter-types="filterTypes"
                show-query-operator
                @remove="removeCondition(ri, ci)"
              />
            </template>
            <li class="list-none">
              <NextButton
                icon="i-lucide-plus"
                blue
                faded
                sm
                :label="t('AUTOMATION.CANVAS.CONFIG.CONDITION.ADD')"
                @click="addCondition(ri)"
              />
            </li>
          </ul>
        </ConfigField>
      </li>
    </ul>

    <NextButton
      icon="i-lucide-plus"
      slate
      faded
      sm
      :label="t('AUTOMATION.CANVAS.CONFIG.ROUTER.ADD_ROUTE')"
      data-testid="router-add-route"
      @click="addRoute"
    />

    <div
      class="flex items-center gap-2 px-3 py-2 text-xs border border-dashed rounded-lg text-n-slate-11 border-n-weak"
      data-testid="router-fallback"
    >
      <span class="rounded-full size-1.5 shrink-0 bg-n-slate-8" />
      {{ t('AUTOMATION.CANVAS.CONFIG.ROUTER.FALLBACK_HINT') }}
    </div>
  </div>
</template>
