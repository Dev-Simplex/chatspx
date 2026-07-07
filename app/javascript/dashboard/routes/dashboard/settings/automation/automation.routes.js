import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Automation from './Index.vue';
import FlowCanvasView from './canvas/FlowCanvasView.vue';

const canvasMeta = {
  featureFlag: FEATURE_FLAGS.AUTOMATIONS,
  permissions: ['administrator'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automation'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'automation_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'automation_list',
          component: Automation,
          meta: {
            featureFlag: FEATURE_FLAGS.AUTOMATIONS,
            permissions: ['administrator'],
          },
        },
      ],
    },
    // Canvas full-bleed: rotas irmãs FORA do SettingsWrapper (que trava max-w-[960px]) — R-10.
    {
      path: frontendURL('accounts/:accountId/settings/automation/canvas/new'),
      name: 'automation_canvas_new',
      component: FlowCanvasView,
      meta: canvasMeta,
    },
    {
      path: frontendURL(
        'accounts/:accountId/settings/automation/canvas/:flowId'
      ),
      name: 'automation_canvas_edit',
      component: FlowCanvasView,
      meta: canvasMeta,
    },
  ],
};
