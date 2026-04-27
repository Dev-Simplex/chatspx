import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

const GalleryPage = () => import('./GalleryPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/gallery'),
    name: 'gallery_index',
    component: GalleryPage,
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
  },
];
