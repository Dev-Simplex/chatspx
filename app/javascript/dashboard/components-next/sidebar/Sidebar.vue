<script setup>
import { h, ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import draggable from 'vuedraggable';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';

import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize } from '@vueuse/core';

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

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const teams = useMapGetter('teams/getMyTeams');
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
              activeOn: [
                'conversation_unassigned',
                'conversation_through_unassigned',
              ],
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
    {
      name: 'Captain',
      icon: lordIcon('captain', 'i-woot-captain'),
      label: t('SIDEBAR.CAPTAIN'),
      activeOn: ['captain_assistants_create_index'],
      children: [
        {
          name: 'FAQs',
          label: t('SIDEBAR.CAPTAIN_RESPONSES'),
          activeOn: [
            'captain_assistants_responses_index',
            'captain_assistants_responses_pending',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_responses_index',
          }),
        },
        {
          name: 'Documents',
          label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
          activeOn: ['captain_assistants_documents_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_documents_index',
          }),
        },
        {
          name: 'Scenarios',
          label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
          activeOn: ['captain_assistants_scenarios_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_scenarios_index',
          }),
        },
        {
          name: 'Playground',
          label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
          activeOn: ['captain_assistants_playground_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_playground_index',
          }),
        },
        {
          name: 'Inboxes',
          label: t('SIDEBAR.CAPTAIN_INBOXES'),
          activeOn: ['captain_assistants_inboxes_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_inboxes_index',
          }),
        },
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_tools_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_tools_index',
          }),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.CAPTAIN_SETTINGS'),
          activeOn: [
            'captain_assistants_settings_index',
            'captain_assistants_guidelines_index',
            'captain_assistants_guardrails_index',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_settings_index',
          }),
        },
        {
          name: 'OpenAI Connection',
          label: t('SIDEBAR.CAPTAIN_OPENAI_CONNECTION'),
          activeOn: ['captain_settings_index'],
          to: accountScopedRoute('captain_settings_index'),
        },
      ],
    },
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
    {
      name: 'Campaigns',
      label: t('SIDEBAR.CAMPAIGNS'),
      icon: lordIcon('megaphone', 'i-lucide-megaphone'),
      children: [
        {
          name: 'Live chat',
          label: t('SIDEBAR.LIVE_CHAT'),
          to: accountScopedRoute('campaigns_livechat_index'),
        },
        {
          name: 'SMS',
          label: t('SIDEBAR.SMS'),
          to: accountScopedRoute('campaigns_sms_index'),
        },
        {
          name: 'WhatsApp',
          label: t('SIDEBAR.WHATSAPP'),
          to: accountScopedRoute('campaigns_whatsapp_index'),
        },
      ],
    },
    {
      name: 'Portals',
      label: t('SIDEBAR.HELP_CENTER.TITLE'),
      icon: lordIcon('helpCenter', 'i-lucide-library-big'),
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
    },
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
        :delay="120"
        delay-on-touch-only
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
        ghost-class="opacity-50"
        @end="onSidebarReorder"
      >
        <template #item="{ element }">
          <SidebarGroup
            v-bind="element"
            :is-collapsed="isEffectivelyCollapsed"
          />
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
        />
      </div>
    </section>
  </aside>
</template>
