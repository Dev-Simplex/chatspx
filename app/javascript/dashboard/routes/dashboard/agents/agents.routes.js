import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from '../../../helper/URLHelper';

const AgentsPageView = () => import('./pages/AgentsPageView.vue');
const AgentsDashboard = () => import('./pages/AgentsDashboard.vue');
const LLMSettingsPage = () => import('./pages/LLMSettingsPage.vue');
const ToolsView = () => import('./pages/ToolsView.vue');
const AgentDetailView = () => import('./pages/AgentDetailView.vue');
const EvaluationPage = () => import('./pages/EvaluationPage.vue');
const RodizioPage = () => import('./pages/RodizioPage.vue');
const RodizioPoliticaPage = () => import('./pages/RodizioPoliticaPage.vue');

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

const meta = {
  permissions: ['administrator'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_V2,
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
    path: 'settings',
    component: SettingsTab,
    name: 'agents_assistant_settings',
    meta,
  },
];

export const routes = [
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
        path: 'rodizio',
        component: RodizioPage,
        name: 'agents_rodizio',
        meta,
      },
      {
        path: 'rodizio/politica',
        component: RodizioPoliticaPage,
        name: 'agents_rodizio_politica',
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
