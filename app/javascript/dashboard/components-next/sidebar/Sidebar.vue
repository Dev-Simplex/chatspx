<script setup>
import { h, ref, computed, onMounted } from 'vue';
import { provideSidebarContext } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';

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

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const store = useStore();
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};
provideSidebarContext({
  expandedItem,
  setExpandedItem,
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

const isCollapsed = computed(
  () => uiSettings.value?.is_sidebar_collapsed ?? false
);

const toggleSidebar = () => {
  updateUISettings({
    is_sidebar_collapsed: !isCollapsed.value,
  });
};

const onComposeOpen = toggleFn => {
  toggleFn();
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
};

const onComposeClose = () => {
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
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
      icon: 'i-lucide-inbox',
      to: accountScopedRoute('inbox_view'),
      activeOn: ['inbox_view', 'inbox_view_conversation'],
      getterKeys: {
        count: 'notifications/getUnreadCount',
      },
    },
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: 'i-lucide-message-circle',
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
          icon: 'i-lucide-clock',
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
              to: accountScopedRoute('conversation_unattended', {}, {
                assignee_type: 'unassigned',
              }),
              count: conversationStats.value?.unattendedUnassignedCount ?? 0,
              highlight:
                (conversationStats.value?.unattendedUnassignedCount ?? 0) > 0,
              tooltip: t('SIDEBAR.UNASSIGNED_CONVERSATIONS_TOOLTIP'),
            },
            {
              name: 'UnattendedAll',
              label: t('SIDEBAR.UNATTENDED_ALL'),
              activeOn: ['conversation_through_unattended'],
              to: accountScopedRoute('conversation_unattended', {}, {
                assignee_type: 'all',
              }),
              count: conversationStats.value?.unattendedAllCount ?? 0,
            },
          ],
        },
        {
          name: 'Status',
          label: t('SIDEBAR.STATUS'),
          icon: 'i-lucide-filter',
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
          icon: 'i-lucide-folder',
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
          icon: 'i-lucide-users',
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
          icon: 'i-lucide-mailbox',
          activeOn: ['conversation_through_inbox'],
          children: sortedInboxes.value.map(inbox => ({
            name: `${inbox.name}-${inbox.id}`,
            label: inbox.name,
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
          icon: 'i-lucide-tag',
          activeOn: ['conversations_through_label'],
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[12px] ring-1 ring-n-alpha-1 dark:ring-white/20 ring-inset rounded-sm`,
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
      icon: 'i-lucide-layout-grid',
      to: accountScopedRoute('kanban_index'),
      activeOn: ['kanban_index', 'kanban_funnel'],
    },
    {
      name: 'Captain',
      icon: 'i-woot-captain',
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
      icon: 'i-lucide-contact',
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
          icon: 'i-lucide-group',
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
          icon: 'i-lucide-tag',
          label: t('SIDEBAR.TAGGED_WITH'),
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[12px] ring-1 ring-n-alpha-1 dark:ring-white/20 ring-inset rounded-sm`,
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
      icon: 'i-lucide-building-2',
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
      icon: 'i-lucide-chart-spline',
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
      icon: 'i-lucide-activity',
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
      icon: 'i-lucide-megaphone',
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
      icon: 'i-lucide-library-big',
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
      icon: 'i-lucide-bolt',
      children: [
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
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
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          to: accountScopedRoute('settings_teams_list'),
        },
        {
          name: 'Settings Agent Assignment',
          label: t('SIDEBAR.AGENT_ASSIGNMENT'),
          icon: 'i-lucide-user-cog',
          to: accountScopedRoute('assignment_policy_index'),
        },
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings WAHA Connections',
          label: t('SIDEBAR.WAHA_CONNECTIONS'),
          icon: h(
            'svg',
            {
              xmlns: 'http://www.w3.org/2000/svg',
              width: '16',
              height: '16',
              fill: 'currentColor',
              viewBox: '0 0 16 16',
              class: 'inline-block',
            },
            [
              h('path', {
                d: 'M13.601 2.326A7.85 7.85 0 0 0 7.994 0C3.627 0 .068 3.558.064 7.926c0 1.399.366 2.76 1.057 3.965L0 16l4.204-1.102a7.9 7.9 0 0 0 3.79.965h.004c4.368 0 7.926-3.558 7.93-7.93A7.9 7.9 0 0 0 13.6 2.326zM7.994 14.521a6.6 6.6 0 0 1-3.356-.92l-.24-.144-2.494.654.666-2.433-.156-.251a6.56 6.56 0 0 1-1.007-3.505c0-3.626 2.957-6.584 6.591-6.584a6.56 6.56 0 0 1 4.66 1.931 6.56 6.56 0 0 1 1.928 4.66c-.004 3.639-2.961 6.592-6.592 6.592m3.615-4.934c-.197-.099-1.17-.578-1.353-.646-.182-.065-.315-.099-.445.099-.133.197-.513.646-.627.775-.114.133-.232.148-.43.05-.197-.1-.836-.308-1.592-.985-.59-.525-.985-1.175-1.103-1.372-.114-.198-.011-.304.088-.403.087-.088.197-.232.296-.346.1-.114.133-.198.198-.33.065-.134.034-.248-.015-.347-.05-.099-.445-1.076-.612-1.47-.16-.389-.323-.335-.445-.34-.114-.007-.247-.007-.38-.007a.73.73 0 0 0-.529.247c-.182.198-.691.677-.691 1.654s.71 1.916.81 2.049c.098.133 1.394 2.132 3.383 2.992.47.205.84.326 1.129.418.475.152.904.129 1.246.08.38-.058 1.171-.48 1.338-.943.164-.464.164-.86.114-.943-.049-.084-.182-.133-.38-.232',
              }),
            ]
          ),
          to: accountScopedRoute('waha_connections_list'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        {
          name: 'Settings Custom Attributes',
          label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
          icon: 'i-lucide-code',
          to: accountScopedRoute('attributes_list'),
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-workflow',
          to: accountScopedRoute('automation_list'),
        },
        {
          name: 'Settings Agent Bots',
          label: t('SIDEBAR.AGENT_BOTS'),
          icon: 'i-lucide-bot',
          to: accountScopedRoute('agent_bots'),
        },
        {
          name: 'Settings Macros',
          label: t('SIDEBAR.MACROS'),
          icon: 'i-lucide-toy-brick',
          to: accountScopedRoute('macros_wrapper'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: 'i-lucide-message-square-quote',
          to: accountScopedRoute('canned_list'),
        },
        {
          name: 'Settings Integrations',
          label: t('SIDEBAR.INTEGRATIONS'),
          icon: 'i-lucide-blocks',
          to: accountScopedRoute('settings_applications'),
        },
        {
          name: 'Settings Audit Logs',
          label: t('SIDEBAR.AUDIT_LOGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('auditlogs_list'),
        },
        {
          name: 'Settings Custom Roles',
          label: t('SIDEBAR.CUSTOM_ROLES'),
          icon: 'i-lucide-shield-plus',
          to: accountScopedRoute('custom_roles_list'),
        },
        {
          name: 'Settings Sla',
          label: t('SIDEBAR.SLA'),
          icon: 'i-lucide-clock-alert',
          to: accountScopedRoute('sla_list'),
        },
        {
          name: 'Settings Security',
          label: t('SIDEBAR.SECURITY'),
          icon: 'i-lucide-shield',
          to: accountScopedRoute('security_settings_index'),
        },
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      { ignore: ['#mobile-sidebar-launcher'] },
    ]"
    class="bg-n-solid-2 rtl:border-l ltr:border-r border-n-weak flex flex-col text-sm pb-1 fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 transition-all duration-200 ease-in-out md:static md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:-translate-x-0"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'w-[64px] basis-[64px]': isCollapsed,
        'w-[200px] basis-[200px]': !isCollapsed,
      },
    ]"
  >
    <section class="grid gap-2 mt-2 mb-4">
      <div class="flex gap-2 items-center px-2 min-w-0">
        <div class="grid flex-shrink-0 place-content-center size-6">
          <Logo class="size-4" />
        </div>
        <div v-if="!isCollapsed" class="flex-shrink-0 w-px h-3 bg-n-strong" />
        <SidebarAccountSwitcher
          class="flex-grow min-w-0 -mx-1"
          v-if="!isCollapsed"
          @show-create-account-modal="emit('showCreateAccountModal')"
        />
        <Button
          v-if="isCollapsed"
          icon="i-lucide-panel-left-open"
          color="slate"
          size="sm"
          class="flex-shrink-0 !h-7 !bg-n-solid-3 dark:!bg-n-black/30 !outline-n-weak !text-n-slate-11"
          :title="t('SIDEBAR.EXPAND')"
          @click="toggleSidebar"
        />
        <Button
          v-else
          icon="i-lucide-panel-left-close"
          color="slate"
          size="sm"
          class="flex-shrink-0 !h-7 !bg-n-solid-3 dark:!bg-n-black/30 !outline-n-weak !text-n-slate-11 ml-auto"
          :title="t('SIDEBAR.COLLAPSE')"
          @click="toggleSidebar"
        />
      </div>
      <div v-if="!isCollapsed" class="flex gap-2 px-2">
        <RouterLink
          :to="{ name: 'search' }"
          class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg outline outline-1 outline-n-weak bg-n-solid-3 dark:bg-n-black/30"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-11" />
          <span class="flex-grow text-left">
            {{ t('SIDEBAR.ADVANCED_SEARCH') }}
          </span>
          <span
            class="hidden tracking-wide pointer-events-none select-none text-n-slate-10"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>
      </div>
      <div v-else class="flex flex-col gap-2 px-2">
        <RouterLink
          :to="{ name: 'search' }"
          class="flex items-center justify-center w-full px-2 py-1 rounded-lg h-7 outline outline-1 outline-n-weak bg-n-solid-3 dark:bg-n-black/30"
          :title="t('SIDEBAR.ADVANCED_SEARCH')"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-11" />
        </RouterLink>
      </div>
    </section>
    <nav
      class="grid flex-grow gap-2 pb-5 overflow-y-scroll no-scrollbar"
      :class="{ 'px-2': !isCollapsed, 'px-1': isCollapsed }"
    >
      <ul class="flex flex-col gap-1.5 m-0 list-none">
        <SidebarGroup
          v-for="item in menuItems"
          :key="item.name"
          v-bind="item"
          :is-collapsed="isCollapsed"
        />
      </ul>
    </nav>
    <section
      class="flex flex-col flex-shrink-0 relative gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[31px] h-8 bg-gradient-to-t from-n-solid-2 to-transparent"
      />
      <SidebarChangelogCard
        v-if="isOnChatwootCloud && !isACustomBrandedInstance"
      />
      <div
        class="p-1 flex-shrink-0 flex w-full justify-between z-10 gap-2 items-center border-t border-n-weak shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
      >
        <SidebarProfileMenu
          :is-collapsed="isCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>
  </aside>
</template>
