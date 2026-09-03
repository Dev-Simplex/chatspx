import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from '../../../helper/URLHelper';

const AgentsPageView = () => import('./pages/AgentsPageView.vue');
const AgentsDashboard = () => import('./pages/AgentsDashboard.vue');
const LLMSettingsPage = () => import('./pages/LLMSettingsPage.vue');
const ToolsView = () => import('./pages/ToolsView.vue');
const AgentDetailView = () => import('./pages/AgentDetailView.vue');
const EvaluationPage = () => import('./pages/EvaluationPage.vue');
const RodizioPage = () => import('./pages/RodizioPage.vue');

const OverviewTab = () =>
  import('dashboard/components-next/agents/tabs/OverviewTab.vue');
const FlowTab = () =>
  import('dashboard/components-next/agents/tabs/FlowTab.vue');
const BehaviorTab = () =>
  import('dashboard/components-next/agents/tabs/BehaviorTab.vue');
const KnowledgeTab = () =>
  import('dashboard/components-next/agents/tabs/KnowledgeTab.vue');
const ScenariosTab = () =>
  import('dashboard/components-next/agents/tabs/ScenariosTab.vue');
const InboxesTab = () =>
  import('dashboard/components-next/agents/tabs/InboxesTab.vue');
const LogsTab = () =>
  import('dashboard/components-next/agents/tabs/LogsTab.vue');
const SettingsTab = () =>
  import('dashboard/components-next/agents/tabs/SettingsTab.vue');
// 6.02 — eval como produto.
const EvalTab = () =>
  import('dashboard/components-next/agents/tabs/EvalTab.vue');

const meta = {
  permissions: ['administrator'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_V2,
};

// O rodizio distribui lead entre corretores; nao tem nada a ver com IA. Herdar o
// `meta` acima o deixava invisivel em qualquer conta sem o Captain ligado - so
// aparecia onde `captain_integration_v2` estava ligada por acaso. Sem featureFlag:
// nenhuma das flags existentes descreve distribuicao de lead (ADVANCED_ASSIGNMENT e
// paywall premium de outro recurso), entao o gate e a permissao de administrador.
const rodizioMeta = {
  permissions: ['administrator'],
};

const agentDetailChildren = [
  {
    path: 'overview',
    component: OverviewTab,
    name: 'agents_assistant_overview',
    meta,
  },
  {
    path: 'flow',
    component: FlowTab,
    name: 'agents_assistant_flow',
    meta,
  },
  {
    path: 'behavior',
    component: BehaviorTab,
    name: 'agents_assistant_behavior',
    meta,
  },
  {
    path: 'knowledge',
    component: KnowledgeTab,
    name: 'agents_assistant_knowledge',
    meta,
  },
  {
    path: 'scenarios',
    component: ScenariosTab,
    name: 'agents_assistant_scenarios',
    meta,
  },
  {
    path: 'inboxes',
    component: InboxesTab,
    name: 'agents_assistant_inboxes',
    meta,
  },
  {
    path: 'logs',
    component: LogsTab,
    name: 'agents_assistant_logs',
    meta,
  },
  {
    path: 'eval',
    component: EvalTab,
    name: 'agents_assistant_eval',
    meta,
  },
  {
    path: 'settings',
    component: SettingsTab,
    name: 'agents_assistant_settings',
    meta,
  },
];

export const routes = [
  // Irmas (e nao filhas) da rota de /agents DE PROPOSITO: como filhas elas
  // renderizavam dentro do AgentsPageView, com a barra lateral "Agentes IA /
  // Nenhum agente encontrado" comendo um terco da tela ao lado de um formulario
  // que nao fala de IA. Vem antes do pai so por leitura; quem garante o casamento
  // e o vue-router, que pontua segmento estatico (`rodizio`) acima de parametro
  // (`:assistantId`).
  {
    path: frontendURL('accounts/:accountId/agents/rodizio'),
    component: RodizioPage,
    name: 'agents_rodizio',
    meta: rodizioMeta,
  },
  // A política do rodízio deixou de ter tela global: ela é POR TIME e passou a morar na edição
  // do time, junto do checkbox de atribuição automática, que é onde o gestor já está quando pensa
  // em quem atende o quê. Duas telas editando a mesma tabela era o achado A4 da auditoria de
  // 26/08 — nenhuma das duas mostrava o que a outra tinha configurado.
  //
  // A rota fica como REDIRECT em vez de sumir: link salvo e favorito de gestor não podem virar
  // 404. Cai na lista de times, que é de onde se escolhe qual time configurar.
  {
    path: frontendURL('accounts/:accountId/agents/rodizio/politica'),
    name: 'agents_rodizio_politica',
    redirect: to => ({ name: 'settings_teams_list', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/agents'),
    component: AgentsPageView,
    children: [
      {
        path: '',
        redirect: to => ({
          name: 'agents_dashboard',
          params: to.params,
        }),
      },
      {
        path: 'dashboard',
        component: AgentsDashboard,
        name: 'agents_dashboard',
        meta,
      },
      {
        path: 'settings',
        component: LLMSettingsPage,
        name: 'agents_settings',
        meta,
      },
      {
        path: 'tools',
        component: ToolsView,
        name: 'agents_tools',
        meta,
      },
      {
        path: 'evaluation',
        component: EvaluationPage,
        name: 'agents_evaluation',
        meta,
      },
      {
        path: ':assistantId',
        component: AgentDetailView,
        redirect: to => ({
          name: 'agents_assistant_overview',
          params: to.params,
        }),
        children: agentDetailChildren,
      },
    ],
  },
];
