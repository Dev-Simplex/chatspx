<script setup>
import { h, ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import unidadesAPI from 'dashboard/api/unidades';
import socialPublicacoesAPI from 'dashboard/api/socialPublicacoes';
import { internalChatNotify } from 'dashboard/helper/internalChatNotify';
import draggable from 'vuedraggable';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';

import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize, onKeyStroke } from '@vueuse/core';

import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import LordIconIcon from 'next/icon/LordIconIcon.vue';
import { LORDICON } from 'dashboard/constants/lordicons';
import { isHelpCenterAuthoringAccount } from 'dashboard/helper/helpCenterEmbed';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const lordIcon = (srcKey, fallback = '') => {
  const cfg = LORDICON[srcKey] || {};
  return h(LordIconIcon, {
    src: cfg.idle,
    srcActive: cfg.active,
    family: cfg.family || 'system',
    fallbackLucide: fallback,
  });
};

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const store = useStore();
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasMessageSequences = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.MESSAGE_SEQUENCES
  );
});

const hasInternalChat = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.INTERNAL_CHAT
  );
});

// Apps de captação de lead por formulário — os mesmos que a tela de campanhas lê.
const LEAD_INTAKE_APPS = ['meta_lead_ads', 'site_leads'];

const appIntegrations = useMapGetter('integrations/getAppIntegrations');

const { isAdmin } = useAdmin();

// Mesma ideia do `hasLeadIntake` logo abaixo: o item some quando a conta nao tem o dado.
// Aqui o gate e por DADO e nao por feature flag de proposito — carregar as unidades liga a
// tela, e nao ha um segundo interruptor para alguem esquecer de ligar. Ver §7 do contrato
// docs/contratos/unidades.md.
const temUnidades = ref(false);
// Gate por DADO, como o item "Campanhas" logo abaixo: a pagina de Rede Social so aparece para
// conta que tem comentario capturado. Conta sem canal de Instagram, ou com o campo `comments`
// nao assinado, nao ganha item nenhum. Ver docs/SPEC-instagram-social.md §7.
const temRedeSocial = ref(false);

// A tela de campanhas só existe para conta que captura lead por formulário: sem hook
// configurado, não há campanha nenhuma para mostrar e o item não aparece.
const hasLeadIntake = computed(() =>
  appIntegrations.value.some(
    app => LEAD_INTAKE_APPS.includes(app.id) && app.hooks?.length > 0
  )
);

// Só a conta autora (conta 3 do deploy de casa) mantém o construtor do Help
// Center; todas as outras contas/VMs veem o portal publicado embutido.
const isHelpCenterAuthoring = computed(() =>
  isHelpCenterAuthoringAccount(accountId.value)
);

// Item "Central de Ajuda" do rail: construtor (conta autora) x iframe (resto).
const helpCenterMenuItem = computed(() => {
  const base = {
    name: 'Portals',
    label: t('SIDEBAR.HELP_CENTER.TITLE'),
    icon: lordIcon('helpCenter', 'i-lucide-library-big'),
  };
  if (!isHelpCenterAuthoring.value) {
    return {
      ...base,
      to: accountScopedRoute('help_center_view'),
      activeOn: ['help_center_view'],
    };
  }
  return {
    ...base,
    children: [
      {
        name: 'Articles',
        label: t('SIDEBAR.HELP_CENTER.ARTICLES'),
        activeOn: [
          'portals_articles_index',
          'portals_articles_new',
          'portals_articles_edit',
        ],
        to: accountScopedRoute('portals_index', {
          navigationPath: 'portals_articles_index',
        }),
      },
      {
        name: 'Categories',
        label: t('SIDEBAR.HELP_CENTER.CATEGORIES'),
        activeOn: [
          'portals_categories_index',
          'portals_categories_articles_index',
          'portals_categories_articles_edit',
        ],
        to: accountScopedRoute('portals_index', {
          navigationPath: 'portals_categories_index',
        }),
      },
      {
        name: 'Locales',
        label: t('SIDEBAR.HELP_CENTER.LOCALES'),
        activeOn: ['portals_locales_index'],
        to: accountScopedRoute('portals_index', {
          navigationPath: 'portals_locales_index',
        }),
      },
      {
        name: 'Settings',
        label: t('SIDEBAR.HELP_CENTER.SETTINGS'),
        activeOn: ['portals_settings_index'],
        to: accountScopedRoute('portals_index', {
          navigationPath: 'portals_settings_index',
        }),
      },
    ],
  };
});

// Real-time @mention toast for internal chat (localized here — the Sidebar is
// always mounted and has i18n; keeps the ActionCable connector i18n-free).
// User notification preferences for internal chat (set in the chat's header).
// Default ON when unset, so existing users keep the prior behavior.
const internalChatSoundEnabled = () =>
  uiSettings.value?.internal_chat_sound_notifications !== false;
const internalChatDesktopEnabled = () =>
  uiSettings.value?.internal_chat_desktop_notifications !== false;
const internalChatTone = () =>
  uiSettings.value?.internal_chat_notification_tone || 'pop.wav';

const pendingInternalMention = useMapGetter('internalChat/getPendingMention');
watch(pendingInternalMention, mention => {
  if (!mention) return;
  const message = t('INTERNAL_CHAT.MENTION_TOAST', {
    from: mention.from,
    channel: mention.channel,
  });
  useAlert(message);
  internalChatNotify({
    title: internalChatDesktopEnabled() ? mention.from : undefined,
    body: message,
    sound: internalChatSoundEnabled(),
    tone: internalChatTone(),
  });
});

// Real-time toast + som para QUALQUER nova mensagem de canais que participo
// (DM/grupo/time) quando não estou olhando aquele canal. Som sempre; toast só
// com a aba visível; notificação desktop só com a aba em segundo plano.
const pendingInternalNotification = useMapGetter(
  'internalChat/getPendingNotification'
);
watch(pendingInternalNotification, notification => {
  if (!notification) return;
  const hidden = typeof document !== 'undefined' && document.hidden;
  if (!hidden) useAlert(`${notification.title}: ${notification.body}`);
  internalChatNotify({
    title:
      internalChatDesktopEnabled() && hidden ? notification.title : undefined,
    body: notification.body,
    sound: internalChatSoundEnabled(),
    tone: internalChatTone(),
  });
});

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

const openCommandPalette = () => {
  const ninja = document.querySelector('ninja-keys');
  if (ninja && typeof ninja.open === 'function') ninja.open();
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const { sidebarWidth } = useSidebarResize();

// WhatsApp-fidelity: desktop rail is ALWAYS collapsed (ícones only).
// Mobile keeps flyout (expanded) behavior untouched.
const isEffectivelyCollapsed = computed(() => !isMobile.value);

const isResizing = ref(false);

// Modo "reordenar barra lateral": ligado pelo item do menu de perfil. Enquanto
// ativo, os ícones do rail ficam arrastáveis (jiggle) e param de navegar. Vai
// pelo contexto (como isCollapsed) porque o SidebarGroup lê estado por injeção.
const reorderMode = ref(false);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
  reorderMode,
});

const inboxes = useMapGetter('inboxes/getInboxes');
// D1 (Fase 3): contador de pedidos de atendimento pendentes (item "Pedidos" só
// aparece quando há algum — sem poluir a sidebar de quem não usa o modo).
const takeoverRequestCount = useMapGetter('takeoverRequests/getIncomingCount');
const labels = useMapGetter('labels/getLabelsOnSidebar');
// Filtro de time da lista de conversas: membro ∪ supervisionado. É o único
// consumidor de `teams` aqui, então nada de etiquetas/respostas "de-time" muda.
const teams = useMapGetter('teams/getVisibleTeams');
const conversationStats = useMapGetter('conversationStats/getStats');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
  // D1 (Fase 3): popula o contador de "Pedidos" no boot (o realtime atualiza
  // depois). Silencioso: sem pedidos, a conta 99% das vezes nem vê o item.
  store.dispatch('takeoverRequests/fetchIncoming').catch(() => {});
  // Carrega os canais do chat interno para o badge de não lidas aparecer (e o
  // tempo-real incrementar) mesmo sem abrir a página do chat.
  if (hasInternalChat.value) store.dispatch('internalChat/fetchChannels');
  // Só para saber se a conta tem captação de lead configurada (o item "Campanhas"
  // some quando não tem). O payload não expõe settings de hook para não-admin.
  if (!appIntegrations.value.length) store.dispatch('integrations/get');
  // So para saber se a conta tem unidade cadastrada (o item "Unidades" some quando nao tem).
  // Admin-only porque o endpoint tambem e — pedir como agente so geraria um 401 por sessao.
  if (isAdmin.value) {
    unidadesAPI
      .getAll()
      .then(({ data }) => {
        temUnidades.value = Boolean(data?.unidades?.length);
      })
      .catch(() => {});
  }
  // So para saber se a conta tem comentario publico capturado (o item "Rede Social" some quando
  // nao tem). Admin-only porque o endpoint tambem e.
  if (isAdmin.value) {
    socialPublicacoesAPI
      .getAll()
      .then(({ data }) => {
        temRedeSocial.value = Boolean(data?.length);
      })
      .catch(() => {});
  }
  setTimeout(() => {
    store.dispatch('conversationStats/get', {});
  }, 2000);
});

const sortedInboxes = computed(() =>
  inboxes.value.slice().sort((a, b) => a.name.localeCompare(b.name))
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Agent Assignment',
    label: t('SIDEBAR.REPORTS_AGENT_ASSIGNMENT'),
    to: accountScopedRoute('agent_assignment_reports'),
  },
  // Aponta para o PAINEL do rodizio, nao para a politica: dali o botao
  // "Configurar rodizio" leva a configuracao. Ate aqui a tela so existia por URL
  // digitada. O item some sozinho para quem nao e admin — o SidebarGroup le
  // `meta.permissions` da rota (provider.js `resolvePermissions`).
  {
    name: 'Reports Rodizio',
    label: t('SIDEBAR.REPORTS_RODIZIO'),
    to: accountScopedRoute('agents_rodizio'),
    activeOn: ['agents_rodizio_politica'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

const menuItems = computed(() => {
  return [
    {
      name: 'Inbox',
      label: t('SIDEBAR.INBOX'),
      icon: lordIcon('notifications', 'i-lucide-bell'),
      to: accountScopedRoute('inbox_view'),
      activeOn: ['inbox_view', 'inbox_view_conversation'],
      getterKeys: {
        count: 'notifications/getUnreadCount',
      },
    },
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: lordIcon('chatMessage', 'i-lucide-message-circle'),
      children: [
        {
          name: 'All',
          label: t('SIDEBAR.ALL_CONVERSATIONS'),
          activeOn: ['inbox_conversation'],
          to: accountScopedRoute('home'),
        },
        {
          name: 'Mentions',
          label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          activeOn: ['conversation_through_mentions'],
          to: accountScopedRoute('conversation_mentions'),
        },
        {
          name: 'UnreadGroup',
          label: t('SIDEBAR.UNREAD_CONVERSATIONS'),
          icon: lordIcon('unattended', 'i-lucide-mail-warning'),
          children: [
            {
              name: 'UnreadMine',
              label: t('SIDEBAR.UNATTENDED_MINE'),
              activeOn: ['conversation_through_unread'],
              to: accountScopedRoute(
                'conversation_unread',
                {},
                {
                  assignee_type: 'me',
                }
              ),
            },
            {
              name: 'UnreadUnassigned',
              label: t('SIDEBAR.UNASSIGNED_CONVERSATIONS'),
              activeOn: ['conversation_through_unread'],
              to: accountScopedRoute(
                'conversation_unread',
                {},
                {
                  assignee_type: 'unassigned',
                }
              ),
            },
            {
              name: 'UnreadAll',
              label: t('SIDEBAR.UNATTENDED_ALL'),
              activeOn: ['conversation_through_unread'],
              to: accountScopedRoute(
                'conversation_unread',
                {},
                {
                  assignee_type: 'all',
                }
              ),
            },
          ],
        },
        {
          name: 'UnattendedGroup',
          label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
          icon: lordIcon('unattended', 'i-lucide-clock'),
          children: [
            {
              name: 'Unattended',
              label: t('SIDEBAR.UNATTENDED_MINE'),
              activeOn: ['conversation_through_unattended'],
              to: accountScopedRoute('conversation_unattended'),
              count: conversationStats.value?.unattendedAssignedCount ?? 0,
              highlight:
                (conversationStats.value?.unattendedAssignedCount ?? 0) > 0,
            },
            {
              name: 'Unassigned',
              label: t('SIDEBAR.UNASSIGNED_CONVERSATIONS'),
              activeOn: ['conversation_through_unattended'],
              to: accountScopedRoute(
                'conversation_unattended',
                {},
                {
                  assignee_type: 'unassigned',
                }
              ),
              count: conversationStats.value?.unattendedUnassignedCount ?? 0,
              highlight:
                (conversationStats.value?.unattendedUnassignedCount ?? 0) > 0,
              tooltip: t('SIDEBAR.UNASSIGNED_CONVERSATIONS_TOOLTIP'),
            },
            {
              name: 'UnattendedAll',
              label: t('SIDEBAR.UNATTENDED_ALL'),
              activeOn: ['conversation_through_unattended'],
              to: accountScopedRoute(
                'conversation_unattended',
                {},
                {
                  assignee_type: 'all',
                }
              ),
              count: conversationStats.value?.unattendedAllCount ?? 0,
            },
          ],
        },
        {
          name: 'Status',
          label: t('SIDEBAR.STATUS'),
          icon: lordIcon('filter', 'i-lucide-filter'),
          activeOn: ['conversation_status', 'conversation_through_status'],
          children: [
            {
              name: 'StatusOpen',
              label: t('SIDEBAR.STATUS_OPEN'),
              to: accountScopedRoute('conversation_status', { status: 'open' }),
              activeOn: ['conversation_status', 'conversation_through_status'],
            },
            {
              name: 'StatusResolved',
              label: t('SIDEBAR.STATUS_RESOLVED'),
              to: accountScopedRoute('conversation_status', {
                status: 'resolved',
              }),
              activeOn: ['conversation_status', 'conversation_through_status'],
            },
            {
              name: 'StatusPending',
              label: t('SIDEBAR.STATUS_PENDING'),
              to: accountScopedRoute('conversation_status', {
                status: 'pending',
              }),
              activeOn: ['conversation_status', 'conversation_through_status'],
            },
            {
              name: 'StatusSnoozed',
              label: t('SIDEBAR.STATUS_SNOOZED'),
              to: accountScopedRoute('conversation_status', {
                status: 'snoozed',
              }),
              activeOn: ['conversation_status', 'conversation_through_status'],
            },
          ],
        },
        {
          name: 'Folders',
          label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          icon: lordIcon('folder', 'i-lucide-folder'),
          activeOn: ['conversations_through_folders'],
          children: conversationCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute('folder_conversations', { id: view.id }),
          })),
        },
        {
          name: 'Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: lordIcon('team', 'i-lucide-users'),
          activeOn: ['conversations_through_team'],
          children: teams.value.map(team => ({
            name: `${team.name}-${team.id}`,
            label: team.name,
            to: accountScopedRoute('team_conversations', { teamId: team.id }),
          })),
        },
        {
          name: 'Channels',
          label: t('SIDEBAR.CHANNELS'),
          icon: lordIcon('channels', 'i-lucide-inbox'),
          activeOn: ['conversation_through_inbox'],
          children: sortedInboxes.value.map(inbox => ({
            name: `${inbox.name}-${inbox.id}`,
            label: inbox.name,
            icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
            to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
            component: leafProps =>
              h(ChannelLeaf, {
                label: leafProps.label,
                active: leafProps.active,
                inbox,
              }),
          })),
        },
        {
          name: 'Labels',
          label: t('SIDEBAR.LABELS'),
          icon: lordIcon('label', 'i-lucide-tag'),
          activeOn: ['conversations_through_label'],
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute('label_conversations', {
              label: label.title,
            }),
          })),
        },
      ],
    },
    {
      name: 'Kanban',
      label: t('SIDEBAR.KANBAN'),
      icon: lordIcon('kanban', 'i-lucide-layout-grid'),
      to: accountScopedRoute('kanban_index'),
      activeOn: ['kanban_index', 'kanban_funnel'],
    },
    {
      name: 'Gallery',
      label: t('SIDEBAR.GALLERY'),
      icon: lordIcon('gallery', 'i-lucide-image'),
      to: accountScopedRoute('gallery_index'),
      activeOn: ['gallery_index'],
    },
    ...(temRedeSocial.value
      ? [
          {
            name: 'Rede Social',
            label: t('SIDEBAR.REDE_SOCIAL'),
            icon: lordIcon('megaphone', 'i-lucide-message-circle'),
            to: accountScopedRoute('social_index'),
            activeOn: ['social_index'],
          },
        ]
      : []),
    ...(takeoverRequestCount.value > 0
      ? [
          {
            name: 'Takeover Requests',
            label: t('SIDEBAR.TAKEOVER_REQUESTS'),
            // Ícone lucide DIRETO (string), não lordIcon: não existe lord 'handRaised',
            // e o LordIconIcon, sem src válido, esconde o fallback após 3s (timeout
            // fixo) e fica em branco. O <Icon> renderiza o span estático na hora.
            icon: 'i-lucide-hand',
            to: accountScopedRoute('takeover_requests_index'),
            activeOn: ['takeover_requests_index'],
            getterKeys: {
              count: 'takeoverRequests/getIncomingCount',
            },
          },
        ]
      : []),
    {
      // Item único (sem submenu): "Conexão LLM" saiu do menu lateral — a
      // config de provedor/modelo passa a viver em "Opções avançadas" do
      // agente. A rota agents_settings segue existindo (acessível direto),
      // por isso fica no activeOn para manter o item destacado.
      name: 'AI Agents',
      icon: lordIcon('captain', 'i-woot-captain'),
      label: t('SIDEBAR.CAPTAIN'),
      to: accountScopedRoute('agents_dashboard'),
      activeOn: [
        'agents_dashboard',
        'agents_settings',
        'agents_tools',
        'agents_evaluation',
      ],
    },
    ...(hasInternalChat.value
      ? [
          {
            name: 'Internal Chat',
            label: t('SIDEBAR.INTERNAL_CHAT'),
            icon: lordIcon('internalChat', 'i-lucide-messages-square'),
            to: accountScopedRoute('internal_chat_index'),
            activeOn: ['internal_chat_index'],
            getterKeys: {
              count: 'internalChat/getTotalUnread',
            },
          },
        ]
      : []),
    {
      name: 'Contacts',
      label: t('SIDEBAR.CONTACTS'),
      icon: lordIcon('contacts', 'i-lucide-contact'),
      children: [
        {
          name: 'All Contacts',
          label: t('SIDEBAR.ALL_CONTACTS'),
          to: accountScopedRoute(
            'contacts_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['contacts_dashboard_index', 'contacts_edit'],
        },
        {
          name: 'Active',
          label: t('SIDEBAR.ACTIVE'),
          to: accountScopedRoute('contacts_dashboard_active'),
          activeOn: ['contacts_dashboard_active'],
        },
        {
          name: 'In Attendance',
          label: t('SIDEBAR.IN_ATTENDANCE'),
          to: accountScopedRoute('contacts_dashboard_in_attendance'),
          activeOn: ['contacts_dashboard_in_attendance'],
        },
        {
          name: 'Segments',
          icon: lordIcon('team', 'i-lucide-group'),
          label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
          children: contactCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute(
              'contacts_dashboard_segments_index',
              { segmentId: view.id },
              { page: 1 }
            ),
            activeOn: [
              'contacts_dashboard_segments_index',
              'contacts_edit_segment',
            ],
          })),
        },
        {
          name: 'Tagged With',
          icon: lordIcon('label', 'i-lucide-tag'),
          label: t('SIDEBAR.TAGGED_WITH'),
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute(
              'contacts_dashboard_labels_index',
              { label: label.title },
              { page: 1, search: undefined }
            ),
            activeOn: [
              'contacts_dashboard_labels_index',
              'contacts_edit_label',
            ],
          })),
        },
      ],
    },
    {
      name: 'Companies',
      label: t('SIDEBAR.COMPANIES'),
      icon: lordIcon('companies', 'i-lucide-building-2'),
      children: [
        {
          name: 'All Companies',
          label: t('SIDEBAR.ALL_COMPANIES'),
          to: accountScopedRoute(
            'companies_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['companies_dashboard_index'],
        },
      ],
    },
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: lordIcon('reports', 'i-lucide-chart-spline'),
      children: [
        {
          name: 'Report Overview',
          label: t('SIDEBAR.REPORTS_OVERVIEW'),
          to: accountScopedRoute('account_overview_reports'),
        },
        {
          name: 'Report Conversation',
          label: t('SIDEBAR.REPORTS_CONVERSATION'),
          to: accountScopedRoute('conversation_reports'),
        },
        ...reportRoutes.value,
        {
          name: 'Reports CSAT',
          label: t('SIDEBAR.CSAT'),
          to: accountScopedRoute('csat_reports'),
        },
        {
          name: 'Reports NPS',
          label: t('SIDEBAR.NPS'),
          to: accountScopedRoute('nps_reports'),
        },
        {
          name: 'Reports SLA',
          label: t('SIDEBAR.REPORTS_SLA'),
          to: accountScopedRoute('sla_reports'),
        },
        {
          name: 'Reports Bot',
          label: t('SIDEBAR.REPORTS_BOT'),
          to: accountScopedRoute('bot_reports'),
        },
      ],
    },
    {
      name: 'Live',
      label: t('SIDEBAR.REPORTS_LIVE'),
      icon: lordIcon('live', 'i-lucide-activity'),
      children: [
        {
          name: 'Live In Service',
          label: t('SIDEBAR.REPORTS_LIVE_IN_SERVICE'),
          to: accountScopedRoute('live_in_service'),
        },
      ],
    },
    ...(hasLeadIntake.value
      ? [
          {
            name: 'Lead Campaigns',
            label: t('SIDEBAR.CAMPAIGNS'),
            icon: lordIcon('megaphone', 'i-lucide-megaphone'),
            to: accountScopedRoute('campaigns_lead_ads_index'),
            activeOn: ['campaigns_lead_ads_index'],
          },
        ]
      : []),
    // {
    //   name: 'Campaigns',
    //   label: t('SIDEBAR.CAMPAIGNS'),
    //   icon: lordIcon('megaphone', 'i-lucide-megaphone'),
    //   children: [
    //     {
    //       name: 'Live chat',
    //       label: t('SIDEBAR.LIVE_CHAT'),
    //       to: accountScopedRoute('campaigns_livechat_index'),
    //     },
    //     {
    //       name: 'SMS',
    //       label: t('SIDEBAR.SMS'),
    //       to: accountScopedRoute('campaigns_sms_index'),
    //     },
    //     {
    //       name: 'WhatsApp',
    //       label: t('SIDEBAR.WHATSAPP'),
    //       to: accountScopedRoute('campaigns_whatsapp_index'),
    //     },
    //   ],
    // },
    helpCenterMenuItem.value,
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: lordIcon('settings', 'i-lucide-bolt'),
      children: [
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: lordIcon('account', 'i-lucide-briefcase'),
          to: accountScopedRoute('general_settings_index'),
        },
        // {
        //   name: 'Settings Captain',
        //   label: t('SIDEBAR.CAPTAIN_AI'),
        //   icon: 'i-woot-captain',
        //   to: accountScopedRoute('captain_settings_index'),
        // },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: lordIcon('agent', 'i-lucide-square-user'),
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: lordIcon('team', 'i-lucide-users'),
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: lordIcon('settings', 'i-lucide-user-cog'),
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: lordIcon('channels', 'i-lucide-inbox'),
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings WAHA Connections',
          label: t('SIDEBAR.WAHA_CONNECTIONS'),
          icon: lordIcon('waha'),
          to: accountScopedRoute('waha_connections_list'),
        },
        ...(temUnidades.value
          ? [
              {
                name: 'Settings Unidades',
                label: t('SIDEBAR.UNIDADES'),
                icon: lordIcon('companies', 'i-lucide-store'),
                activeOn: ['unidades_list'],
                to: accountScopedRoute('unidades_list'),
              },
            ]
          : []),
        ...(hasMessageSequences.value
          ? [
              {
                name: 'Settings Message Sequences',
                label: t('SIDEBAR.MESSAGE_SEQUENCES'),
                icon: lordIcon('automation', 'i-lucide-mails'),
                activeOn: ['message_sequences_index'],
                to: accountScopedRoute('message_sequences_index'),
              },
            ]
          : []),
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: lordIcon('label', 'i-lucide-tags'),
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: lordIcon('customAttrs', 'i-lucide-code'),
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: lordIcon('automation', 'i-lucide-repeat'),
          to: accountScopedRoute('automation_list'),
        },
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: lordIcon('bots', 'i-lucide-bot'),
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: lordIcon('macros', 'i-lucide-toy-brick'),
          to: accountScopedRoute('macros_wrapper'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: lordIcon('cannedResp', 'i-lucide-message-square-quote'),
          to: accountScopedRoute('canned_list'),
        },
        {
          name: 'Settings Integrations',
          label: t('SIDEBAR.INTEGRATIONS'),
          icon: lordIcon('integration', 'i-lucide-blocks'),
          to: accountScopedRoute('settings_applications'),
        },
        {
          name: 'Settings Audit Logs',
          label: t('SIDEBAR.AUDIT_LOGS'),
          icon: lordIcon('audit', 'i-lucide-briefcase'),
          to: accountScopedRoute('auditlogs_list'),
        },
        {
          name: 'Settings Custom Roles',
          label: t('SIDEBAR.CUSTOM_ROLES'),
          icon: lordIcon('customRoles', 'i-lucide-shield-plus'),
          to: accountScopedRoute('custom_roles_list'),
        },
        {
          name: 'Settings Sla',
          label: t('SIDEBAR.SLA'),
          icon: lordIcon('sla', 'i-lucide-clock-alert'),
          to: accountScopedRoute('sla_list'),
        },
        {
          name: 'Conversation Workflow',
          label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
          icon: lordIcon('workflow', 'i-lucide-workflow'),
          to: accountScopedRoute('conversation_workflow_index'),
        },
        {
          name: 'Settings Security',
          label: t('SIDEBAR.SECURITY'),
          icon: lordIcon('customRoles', 'i-lucide-shield'),
          to: accountScopedRoute('security_settings_index'),
        },
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: lordIcon('billing', 'i-lucide-credit-card'),
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});

// WA-style rail: show ALL top-level items, sempre como ícones (collapsed).
// Tooltip no hover mostra o label. Admin itens permanecem acessíveis.
const orderedMenuItems = computed(() => {
  const order = Array.isArray(uiSettings.value?.sidebar_order)
    ? uiSettings.value.sidebar_order
    : [];
  if (!order.length) return menuItems.value;
  const byName = Object.fromEntries(
    menuItems.value.map(item => [item.name, item])
  );
  const ordered = order.map(name => byName[name]).filter(Boolean);
  const remaining = menuItems.value.filter(item => !order.includes(item.name));
  return [...ordered, ...remaining];
});

const visibleMenuItems = computed(() => orderedMenuItems.value);

// Live ref synced with computed — vuedraggable mutates this array
// then we persist the resulting order to uiSettings.
const liveMenuItems = ref([]);
watch(
  visibleMenuItems,
  v => {
    liveMenuItems.value = [...v];
  },
  { immediate: true }
);

const onSidebarReorder = () => {
  const newOrder = liveMenuItems.value.map(item => item.name);
  updateUISettings({ sidebar_order: newOrder });
};

const enterReorderMode = () => {
  reorderMode.value = true;
};

const exitReorderMode = () => {
  reorderMode.value = false;
};

// Restaura a ordem padrão: zera sidebar_order — orderedMenuItems cai de volta na
// ordem natural de menuItems e liveMenuItems re-sincroniza pelo watch existente.
const resetSidebarOrder = () => {
  updateUISettings({ sidebar_order: [] });
};

// Esc sai do modo reordenar.
onKeyStroke('Escape', () => {
  if (reorderMode.value) exitReorderMode();
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      { ignore: ['#mobile-sidebar-launcher'] },
    ]"
    class="bg-n-background flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[200px] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-n-weak"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="
      isMobile
        ? undefined
        : { width: isEffectivelyCollapsed ? '72px' : `${sidebarWidth}px` }
    "
  >
    <section
      class="grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-2 gap-3' : 'mt-1 mb-4 gap-2'"
    >
      <div
        class="flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1': isEffectivelyCollapsed,
          'px-2': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <SidebarAccountSwitcher
            is-collapsed
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
        <template v-else>
          <div class="grid flex-shrink-0 place-content-center size-6">
            <Logo class="size-4" />
          </div>
          <div class="flex-shrink-0 w-px h-3 bg-n-strong" />
          <SidebarAccountSwitcher
            class="flex-grow -mx-1 min-w-0"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
      </div>
      <div
        class="flex gap-2 min-w-0"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-2'"
      >
        <button
          v-if="!isEffectivelyCollapsed"
          data-hover-host
          type="button"
          class="flex gap-2 items-center px-3 py-2 w-full min-w-0 overflow-hidden rounded-lg bg-n-slate-3 hover:bg-n-slate-4 dark:bg-n-slate-9/40 dark:hover:bg-n-slate-9/60 text-n-slate-11 text-sm transition-colors duration-100 ease-out"
          @click="openCommandPalette"
        >
          <LordIconIcon
            :src="LORDICON.search.idle"
            :src-active="LORDICON.search.active"
            :family="LORDICON.search.family"
            fallback-lucide="i-lucide-search"
            :size="16"
            class="flex-shrink-0"
          />
          <span class="flex-1 min-w-0 text-start truncate">
            {{ t('SIDEBAR.SEARCH_PLACEHOLDER') }}
          </span>
          <kbd
            class="hidden xl:inline-flex flex-shrink-0 text-[11px] bg-n-slate-1 dark:bg-n-slate-9 border border-n-slate-6 text-n-slate-11 px-1.5 py-0.5 rounded font-mono leading-none tracking-wide pointer-events-none select-none"
          >
            {{ searchShortcut }}
          </kbd>
        </button>
        <RouterLink
          v-else
          v-tooltip.right="t('SIDEBAR.SEARCH_PLACEHOLDER')"
          data-hover-host
          :to="{ name: 'search' }"
          class="flex items-center justify-center size-10 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 [&_svg]:opacity-60 hover:[&_svg]:opacity-100 transition-colors duration-150"
          :title="t('SIDEBAR.SEARCH_PLACEHOLDER')"
        >
          <LordIconIcon
            :src="LORDICON.search.idle"
            :src-active="LORDICON.search.active"
            :family="LORDICON.search.family"
            fallback-lucide="i-lucide-search"
            :size="18"
            class="text-current"
          />
        </RouterLink>
      </div>
    </section>
    <nav
      class="grid overflow-y-auto flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <draggable
        v-model="liveMenuItems"
        tag="ul"
        item-key="name"
        :animation="150"
        :disabled="!reorderMode"
        :delay="0"
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
        ghost-class="opacity-50"
        @end="onSidebarReorder"
      >
        <template #item="{ element }">
          <SidebarGroup v-bind="element" :is-collapsed="isCollapsed" />
        </template>
      </draggable>
    </nav>
    <section
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-n-background to-transparent"
      />
      <SidebarChangelogCard
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          isEffectivelyCollapsed
        "
      />
      <div
        class="px-1 py-1.5 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-n-weak shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
          @enter-reorder-mode="enterReorderMode"
        />
      </div>
    </section>

    <!-- Barra flutuante do modo reordenar. Teleportada pro body porque o <aside>
         tem transform (translate-x), o que quebraria position:fixed relativo. -->
    <Teleport to="body">
      <div
        v-if="reorderMode"
        class="fixed bottom-6 left-1/2 z-[100] flex -translate-x-1/2 items-center gap-1.5 p-1.5 max-w-[calc(100vw-1rem)] rounded-full border shadow-lg whitespace-nowrap bg-n-background border-n-weak text-n-slate-12"
      >
        <span
          class="flex flex-shrink-0 gap-2 items-center text-sm ltr:pl-2.5 rtl:pr-2.5 text-n-slate-11"
        >
          <span class="flex-shrink-0 size-4 i-lucide-arrow-up-down" />
          {{ t('SIDEBAR.REORDER.HINT') }}
        </span>
        <button
          type="button"
          class="flex flex-shrink-0 gap-1.5 items-center py-1.5 ltr:pl-2.5 ltr:pr-3 rtl:pr-2.5 rtl:pl-3 text-sm rounded-full transition-colors text-n-slate-11 hover:bg-n-alpha-2"
          @click="resetSidebarOrder"
        >
          <span class="flex-shrink-0 size-4 i-lucide-rotate-ccw" />
          {{ t('SIDEBAR.REORDER.RESET') }}
        </button>
        <button
          type="button"
          class="flex flex-shrink-0 gap-1.5 items-center py-1.5 ltr:pl-3 ltr:pr-4 rtl:pr-3 rtl:pl-4 text-sm font-medium text-white rounded-full transition-colors bg-n-brand hover:opacity-90"
          @click="exitReorderMode"
        >
          <span class="flex-shrink-0 size-4 i-lucide-check" />
          {{ t('SIDEBAR.REORDER.DONE') }}
        </button>
      </div>
    </Teleport>
  </aside>
</template>
