import { frontendURL } from '../../../helper/URLHelper';
import ContactsIndex from './pages/ContactsIndex.vue';
import AttendanceIndex from './pages/AttendanceIndex.vue';
import ContactManageView from './pages/ContactManageView.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent', 'contact_manage'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contacts'),
    component: ContactsIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_dashboard_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_dashboard_segments_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_dashboard_labels_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'active',
        name: 'contacts_dashboard_active',
        component: ContactsIndex,
        meta: commonMeta,
      },
    ],
  },
  {
    // Rota IRMÃ, não filha de /contacts: o pai renderiza ContactsIndex e não tem
    // <router-view>, então o `component` de uma filha seria ignorado (é por isso
    // que todas as filhas apontam p/ ContactsIndex e a página decide pelo
    // route.name). Segmento estático ganha de `contacts/:contactId` no ranking
    // do vue-router — mesmo caso da aba `active`, que já convive com ela.
    path: frontendURL('accounts/:accountId/contacts/in-attendance'),
    name: 'contacts_dashboard_in_attendance',
    component: AttendanceIndex,
    meta: commonMeta,
  },
  {
    path: frontendURL('accounts/:accountId/contacts/:contactId'),
    component: ContactManageView,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_edit',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_edit_segment',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_edit_label',
        component: ContactManageView,
        meta: commonMeta,
      },
    ],
  },
];
