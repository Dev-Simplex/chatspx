import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../../featureFlags';

import TeamsIndex from './Index.vue';
import CreateStepWrap from './Create/Index.vue';
import EditStepWrap from './Edit/Index.vue';
import CreateTeam from './Create/CreateTeam.vue';
import EditTeam from './Edit/EditTeam.vue';
import AddAgents from './Create/AddAgents.vue';
import EditAgents from './Edit/EditAgents.vue';
import EditDistribuicao from './Edit/EditDistribuicao.vue';
import FinishSetup from './FinishSetup.vue';
import SettingsContent from '../Wrapper.vue';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/teams'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'settings_teams_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'settings_teams_list',
          component: TeamsIndex,
          meta: {
            featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
            // Supervisor de time entra aqui em modo reduzido: vê apenas os times
            // que supervisiona e compõe os MEMBROS deles (adicionar/remover, com
            // o pool fechado no backend). Criar/editar/excluir time continua
            // exclusivo de admin — tanto no botão (Index.vue) quanto nas rotas
            // filhas, que seguem `['administrator']`.
            permissions: ['administrator', 'team_supervisor'],
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/teams'),
      component: SettingsContent,
      props: () => {
        return {
          headerTitle: 'TEAMS_SETTINGS.HEADER',
          icon: 'people-team',
          showBackButton: true,
        };
      },
      children: [
        {
          path: 'new',
          component: CreateStepWrap,
          children: [
            {
              path: '',
              name: 'settings_teams_new',
              component: CreateTeam,
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
            },
            {
              path: ':teamId/finish',
              name: 'settings_teams_finish',
              component: FinishSetup,
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
            },
            {
              path: ':teamId/agents',
              name: 'settings_teams_add_agents',
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
              component: AddAgents,
            },
          ],
        },
        {
          path: ':teamId/edit',
          component: EditStepWrap,
          children: [
            {
              path: '',
              name: 'settings_teams_edit',
              component: EditTeam,
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
            },
            {
              path: 'agents',
              name: 'settings_teams_edit_members',
              component: EditAgents,
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
            },
            {
              path: 'distribuicao',
              name: 'settings_teams_edit_distribuicao',
              component: EditDistribuicao,
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                // O gerente do time entra aqui — mesma dupla de permissões que a
                // tela de Times do supervisor já usa. Quem sabe quem entra de
                // férias convive com a equipe; o backend valida de novo.
                permissions: ['administrator', 'team_supervisor'],
              },
            },
            {
              path: 'finish',
              name: 'settings_teams_edit_finish',
              meta: {
                featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
                permissions: ['administrator'],
              },
              component: FinishSetup,
            },
          ],
        },
      ],
    },
  ],
};
