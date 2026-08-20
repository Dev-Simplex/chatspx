import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import ReportsWrapper from './components/ReportsWrapper.vue';
import Index from './Index.vue';

import AgentReportsIndex from './AgentReportsIndex.vue';
import AgentAssignmentReports from './AgentAssignmentReports.vue';
import InboxReportsIndex from './InboxReportsIndex.vue';
import TeamReportsIndex from './TeamReportsIndex.vue';
import LabelReportsIndex from './LabelReportsIndex.vue';

import AgentReportsShow from './AgentReportsShow.vue';
import InboxReportsShow from './InboxReportsShow.vue';
import TeamReportsShow from './TeamReportsShow.vue';
import LabelReportsShow from './LabelReportsShow.vue';

import AgentReports from './AgentReports.vue';
import InboxReports from './InboxReports.vue';
import LabelReports from './LabelReports.vue';
import TeamReports from './TeamReports.vue';

import CsatResponses from './CsatResponses.vue';
import NetPromoterScoreReports from './NetPromoterScoreReports.vue';
import BotReports from './BotReports.vue';
import LiveReports from './LiveReports.vue';
import SLAReports from './SLAReports.vue';
import LiveInService from './LiveInService.vue';
import ConversationOriginReports from './ConversationOriginReports.vue';

const meta = {
  featureFlag: FEATURE_FLAGS.REPORTS,
  permissions: ['administrator', 'report_manage'],
};

const oldReportRoutes = [
  {
    path: 'agent',
    name: 'agent_reports',
    meta,
    component: AgentReports,
  },
  {
    path: 'inboxes',
    name: 'inbox_reports',
    meta,
    component: InboxReports,
  },
  {
    path: 'label',
    name: 'label_reports',
    meta,
    component: LabelReports,
  },
  {
    path: 'teams',
    name: 'team_reports',
    meta,
    component: TeamReports,
  },
];

const revisedReportRoutes = [
  {
    path: 'agents_overview',
    name: 'agent_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsIndex,
  },
  {
    path: 'agents/:id',
    name: 'agent_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsShow,
  },
  {
    path: 'assignments',
    name: 'agent_assignment_reports',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentAssignmentReports,
  },

  {
    path: 'inboxes_overview',
    name: 'inbox_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsIndex,
  },
  {
    path: 'inboxes/:id',
    name: 'inbox_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsShow,
  },
  {
    path: 'teams_overview',
    name: 'team_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsIndex,
  },
  {
    path: 'teams/:id',
    name: 'team_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsShow,
  },
  {
    path: 'labels_overview',
    name: 'label_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsIndex,
  },
  {
    path: 'labels/:id',
    name: 'label_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsShow,
  },
  // Bloco 1.22 — de onde vieram os atendimentos.
  {
    path: 'origin',
    name: 'conversation_origin_reports',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: ConversationOriginReports,
  },
];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/reports'),
      component: ReportsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'account_overview_reports', params: to.params };
          },
        },
        {
          path: 'overview',
          name: 'account_overview_reports',
          meta,
          component: LiveReports,
        },
        {
          path: 'conversation',
          name: 'conversation_reports',
          meta,
          component: Index,
        },
        ...oldReportRoutes,
        ...revisedReportRoutes,
        {
          path: 'sla',
          name: 'sla_reports',
          meta,
          component: SLAReports,
        },
        {
          path: 'csat',
          name: 'csat_reports',
          meta,
          component: CsatResponses,
        },
        {
          path: 'nps',
          name: 'nps_reports',
          meta,
          component: NetPromoterScoreReports,
        },
        {
          path: 'bot',
          name: 'bot_reports',
          meta,
          component: BotReports,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/live'),
      component: ReportsWrapper,
      children: [
        {
          // Mesmo motivo do redirect em /reports: sem um filho para o path vazio,
          // /live cru nao resolve para rota nenhuma e o router tenta um
          // replaceState com URL undefined (SecurityError em navegacao client-side).
          path: '',
          redirect: to => ({ name: 'live_in_service', params: to.params }),
        },
        {
          path: 'in_service',
          name: 'live_in_service',
          meta,
          component: LiveInService,
        },
      ],
    },
  ],
};
