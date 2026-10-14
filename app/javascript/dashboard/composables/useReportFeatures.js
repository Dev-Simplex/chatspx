import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

// O que a conta ligou e, por isso, tem relatório para mostrar. Satisfação (CSAT) e
// Indicação (NPS) são ligadas por caixa de entrada; Prazos (SLA), criando uma regra em
// Configurações. O que não está ligado some do menu, das abas e do Painel, e aparece
// sozinho quando alguém liga.
let slaRequested = false;

export const useReportFeatures = () => {
  const store = useStore();
  const inboxes = useMapGetter('inboxes/getInboxes');
  const slaPolicies = useMapGetter('sla/getSLA');

  // As caixas o menu lateral já carrega; as regras de SLA, só uma vez por sessão.
  if (!slaRequested) {
    slaRequested = true;
    store.dispatch('sla/get').catch(() => {});
  }

  const enabled = computed(() => ({
    csat: inboxes.value.some(inbox => inbox.csat_survey_enabled),
    nps: inboxes.value.some(inbox => inbox.nps_survey_enabled),
    sla: slaPolicies.value.length > 0,
  }));

  // Rota de relatório que depende de algo desligado.
  const ROUTE_FEATURE = {
    csat_reports: 'csat',
    nps_reports: 'nps',
    sla_reports: 'sla',
  };
  const isReportEnabled = routeName => {
    const feature = ROUTE_FEATURE[routeName];
    return !feature || enabled.value[feature];
  };

  return { enabled, isReportEnabled };
};
