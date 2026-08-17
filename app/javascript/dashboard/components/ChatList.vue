<script setup>
import { ref, unref, provide, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import ConversationList from './ConversationList.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ConversationSearchModal from './widgets/conversation/ConversationSearchModal.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';
import AssignAndResolveDialog from 'dashboard/components-next/Conversation/AssignAndResolveDialog.vue';
import { useResolveAssignmentGate } from 'dashboard/composables/useResolveAssignmentGate';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { losesConversationAccess } from 'dashboard/helper/conversationAccessHelper';
import {
  conversationListPageURL,
  conversationUrl,
  frontendURL,
} from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
  isOnUnreadView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';
import {
  UNREAD_ROUTES,
  resolveAssigneeTab,
} from 'dashboard/helper/unreadViewHelper';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  conversationStatus: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

const resolveAttributesModalRef = ref(null);

// activeAssigneeTab is initialized after assigneeTabItems (below) so the default
// can be clamped to the tabs the user is actually allowed to see.
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const showSearchModal = ref(false);
// Local cache for search results — completely isolated from Vuex lifecycle
// Only cleared by explicit user action (empty input, X button, Escape)
const cachedSearchResults = ref([]);
const cachedSearchQuery = ref('');
const appliedFilter = ref([]);
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unAssignedChatsList = useMapGetter('getUnAssignedChats');
const aiChatsList = useMapGetter('getAIChats');
const awaitingChatsList = useMapGetter('getAwaitingChats');
const pendingClosureChatsList = useMapGetter('getPendingClosureChats');
const participatingChatsList = useMapGetter('getParticipatingChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
const currentRole = useMapGetter('getCurrentRole');
const myTeams = useMapGetter('teams/getMyTeams');
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

// AI tabs (Fase C — C4): gated by the reply_assignment_gate account setting.
// As abas dinâmicas (Aguardando atendimento / IA) dependem dos contadores do
// /meta (awaitingCount / aiCount), não da existência de assistentes Captain.
const { isAssignmentGateEnabled } = useReplyAssignmentGate();
const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

const {
  requiresAssignmentToResolve,
  getResolveVariant,
  getAssignee,
  hasTeam,
  assignSelfAndResolve,
} = useResolveAssignmentGate();

// "Atribuição obrigatória" — assign-and-resolve dialog state for the context menu.
const showAssignResolveDialog = ref(false);
const assignResolveContext = ref({
  conversationId: null,
  snoozedUntil: null,
  variant: 'unassigned',
  assigneeName: '',
  requiresTeam: false,
});

function openAssignResolveDialog(conversation, snoozedUntil) {
  const variant = getResolveVariant(conversation);
  const assignee = getAssignee(conversation);
  assignResolveContext.value = {
    conversationId: conversation.id,
    snoozedUntil,
    variant,
    assigneeName:
      variant === 'ai'
        ? assignee?.name ||
          t('CONVERSATION.RESOLVE_ASSIGNMENT_GATE.AI_FALLBACK')
        : assignee?.name || '',
    requiresTeam: !hasTeam(conversation),
  };
  showAssignResolveDialog.value = true;
}

function closeAssignResolveDialog() {
  showAssignResolveDialog.value = false;
}

async function handleAssignAndResolve({ teamId }) {
  const { conversationId, snoozedUntil } = assignResolveContext.value;
  closeAssignResolveDialog();
  try {
    await assignSelfAndResolve(conversationId, { teamId, snoozedUntil });
    useAlert(t('CONVERSATION.RESOLVE_ASSIGNMENT_GATE.SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
  }
}

// computed

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const getContact = useMapGetter('contacts/getContact');
const folderContactId = useMapGetter('customViews/getActiveFolderContactId');

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

// Keys the user is allowed to use by *permission* (role/custom-role), before
// any UI-level filtering of the tab-bar. The gate ON hides the "unassigned"
// chip from the tab-bar (it lives in the sidebar instead), but the user may
// still legitimately land on the unassigned queue via that sidebar item /
// deep-link. Clamping must respect permission, not tab-bar visibility — so
// resolveAssigneeTab uses these keys, keeping the security clamp intact for
// roles that genuinely lack the permission.
const permittedAssigneeTabKeys = computed(() =>
  filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key }) => key)
);

const assigneeTabItems = computed(() => {
  const useUnattendedCounts = props.conversationType === 'unattended';
  const countKeyForTab = key => {
    if (useUnattendedCounts) {
      if (key === wootConstants.ASSIGNEE_TYPE.ME)
        return 'unattendedAssignedCount';
      if (key === wootConstants.ASSIGNEE_TYPE.UNASSIGNED)
        return 'unattendedUnassignedCount';
      if (key === wootConstants.ASSIGNEE_TYPE.ALL) return 'allCount';
    }
    return ASSIGNEE_TYPE_TAB_PERMISSIONS[key]?.count ?? 'allCount';
  };
  const stats = conversationStats.value;
  const iconForKey = key => {
    if (key === wootConstants.ASSIGNEE_TYPE.ME) return 'i-lucide-user';
    if (key === wootConstants.ASSIGNEE_TYPE.AWAITING) return 'i-lucide-clock';
    if (key === wootConstants.ASSIGNEE_TYPE.UNASSIGNED)
      return 'i-lucide-user-round-x';
    if (key === wootConstants.ASSIGNEE_TYPE.AI) return 'i-lucide-sparkles';
    if (key === wootConstants.ASSIGNEE_TYPE.PENDING_CLOSURE)
      return 'i-lucide-check-check';
    if (key === wootConstants.ASSIGNEE_TYPE.ALL) return 'i-lucide-users';
    return null;
  };
  const items = filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  )
    .filter(({ key }) => {
      // Dynamic tabs (modo IA / gate ON): só aparecem quando têm conteúdo.
      // "Aguardando atendimento": gate ON + awaiting_count > 0, fora da visão
      // de não-respondidas (sem contadores per-awaiting nessa visão).
      if (key === wootConstants.ASSIGNEE_TYPE.AWAITING)
        return (
          isAssignmentGateEnabled.value &&
          !useUnattendedCounts &&
          (stats.awaitingCount ?? 0) > 0
        );
      // "IA": gate ON + ai_count > 0 (antes dependia de hasCaptainAgents — agora
      // a aba só aparece quando de fato há conversas com a IA), fora da visão de
      // não-respondidas (sem contadores per-AI — OQ-2).
      if (key === wootConstants.ASSIGNEE_TYPE.AI)
        return (
          isAssignmentGateEnabled.value &&
          !useUnattendedCounts &&
          (stats.aiCount ?? 0) > 0
        );
      // "Aguardando encerramento": gate ON + awaiting_closure_count > 0.
      if (key === wootConstants.ASSIGNEE_TYPE.PENDING_CLOSURE)
        return (
          isAssignmentGateEnabled.value &&
          !useUnattendedCounts &&
          (stats.awaitingClosureCount ?? 0) > 0
        );
      // Gate ON: "Não atribuídas" deixa de ser chip da tab-bar no modo IA
      // (a fila vira "Aguardando atendimento"). Modo clássico mantém
      // "Não atribuídas" como aba normal (return true abaixo).
      if (
        key === wootConstants.ASSIGNEE_TYPE.UNASSIGNED &&
        isAssignmentGateEnabled.value &&
        !useUnattendedCounts
      )
        return false;
      return true;
    })
    .map(({ key }) => {
      return {
        key,
        name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
        count: stats[countKeyForTab(key)] ?? 0,
        icon: iconForKey(key),
        // "Aguardando atendimento" recebe o efeito de atenção em vermelho
        // (.tab-alert: ruby + jump-in), no mesmo espírito da fila de IA.
        variant:
          key === wootConstants.ASSIGNEE_TYPE.AWAITING ? 'alert' : undefined,
      };
    });
  return items;
});

// Route-aware default tab, clamped to the tabs the user is allowed to use by
// permission (not just the ones rendered in the tab-bar) so the dedicated
// "Aguardando atendimento" route / sidebar deep-link can select the unassigned
// tab even though the gate hides its chip from the tab-bar.
const activeAssigneeTab = ref(
  resolveAssigneeTab(route.name, route.query, permittedAssigneeTabKeys.value)
);

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.AI
  );
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : activeAssigneeTab.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  activeAssigneeTab
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  // Optional chaining: the conditional "Unassigned" tab can vanish while
  // still active for one tick before the fallback watcher kicks in.
  const count = assigneeTabItems.value.find(
    item => item.key === activeAssigneeTab.value
  )?.count;
  return count ?? 0;
});

const conversationListPagination = computed(() => {
  const conversationsPerPage = 25;
  const visibleChats = Array.isArray(chatsOnView.value)
    ? chatsOnView.value
    : [];
  const visibleCount = visibleChats.length;
  const tabCount = activeAssigneeTabCount.value;

  const isChatListEmpty = visibleCount === 0;
  const isDefaultView = !hasAppliedFiltersOrActiveFolders.value;
  // The rendered list is empty (e.g. right after a tab switch/reset) but the
  // tab's total count says there is still a partial page (1..24) left to load.
  // Re-fetch from page 1 instead of advancing the cursor past the data.
  const hasUnloadedPartialPage =
    tabCount > visibleCount && tabCount < conversationsPerPage;

  if (isDefaultView && isChatListEmpty && hasUnloadedPartialPage) {
    return 1;
  }

  return currentPage.value + 1;
});

const dateRangeFilter = ref(null);

const conversationFilters = computed(() => {
  const filterKey = activeAssigneeTab.value;
  const nextCursor =
    store.getters['conversationPage/getNextCursor']?.(filterKey);
  return {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType: activeAssigneeTab.value,
    status: activeStatus.value,
    sortBy: activeSortBy.value,
    page: nextCursor ? undefined : conversationListPagination.value,
    cursor: nextCursor || undefined,
    labels: props.label ? [props.label] : undefined,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    dateFrom: dateRangeFilter.value?.from || undefined,
    dateTo: dateRangeFilter.value?.to || undefined,
  };
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const searchContext = computed(() => {
  return {
    teamId: props.teamId || undefined,
    inboxId: props.conversationInbox || undefined,
    label: props.label || undefined,
    conversationType: props.conversationType || undefined,
    foldersId: props.foldersId || undefined,
  };
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    return `#${props.label}`;
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.MENTION) {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (
    props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
  ) {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.UNATTENDED) {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (props.conversationType === 'unread') {
    return t('CHAT_LIST.UNREAD_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

const searchResults = computed(
  () => store.getters['conversationSearch/getConversationRecords'] || []
);

const conversationSearchQuery = computed(
  () => store.getters['conversationSearch/getConversationSearchQuery'] || ''
);

const isSearchActive = computed(() => {
  const active =
    cachedSearchQuery.value.length > 0 || cachedSearchResults.value.length > 0;
  return active;
});

// Mostrar empty state "nenhum resultado" só depois que a API de busca respondeu (não antes nem durante o loading)
const conversationSearchCompleted = computed(
  () =>
    store.getters['conversationSearch/getConversationSearchCompleted'] || false
);

// Sync Vuex search results to local cache when new results arrive
watch(searchResults, newResults => {
  if (newResults && newResults.length > 0) {
    cachedSearchResults.value = [...newResults];
  }
});

// Sync Vuex search query to local cache
watch(conversationSearchQuery, newQuery => {
  if (newQuery && newQuery.trim().length > 0) {
    cachedSearchQuery.value = newQuery.trim();
  }
});

const showSearchNoResults = computed(() => {
  return (
    cachedSearchQuery.value.length > 0 &&
    conversationSearchCompleted.value &&
    cachedSearchResults.value.length === 0
  );
});

function filterByAssigneeTab(conversations) {
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ME) {
    return conversations.filter(
      c => c.meta?.assignee?.id === currentUser.value?.id
    );
  }
  if (activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.UNASSIGNED) {
    return conversations.filter(c => !c.meta?.assignee);
  }
  return [...conversations];
}

function sortByUnreadStatus(conversations) {
  return [...conversations].sort((a, b) => {
    const unreadCountDiff = (b.unread_count || 0) - (a.unread_count || 0);
    if (unreadCountDiff !== 0) return unreadCountDiff;

    return (b.last_activity_at || 0) - (a.last_activity_at || 0);
  });
}

const conversationList = computed(() => {
  // Search mode: use local cached results (immune to Vuex/WebSocket/route changes)
  if (isSearchActive.value) {
    let filteredResults = [...cachedSearchResults.value];

    // Deduplicar por contato — mostrar só a conversa mais recente de cada contato
    const byContact = new Map();
    filteredResults.forEach(conv => {
      const contactId =
        conv.contact?.id || conv.meta?.sender?.id || `conv_${conv.id}`;
      const existing = byContact.get(contactId);
      if (!existing) {
        byContact.set(contactId, conv);
      } else {
        const existingTime =
          existing.last_activity_at || existing.created_at || 0;
        const currentTime = conv.last_activity_at || conv.created_at || 0;
        if (currentTime > existingTime) {
          byContact.set(contactId, conv);
        }
      }
    });
    return Array.from(byContact.values());
  }

  // Lógica original quando busca não está ativa
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    if (
      props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
    ) {
      localConversationList = filterByAssigneeTab(
        participatingChatsList.value(filters)
      );
    } else if (activeAssigneeTab.value === 'me') {
      localConversationList = mineChatsList.value;
    } else if (activeAssigneeTab.value === 'unassigned') {
      localConversationList = unAssignedChatsList.value;
    } else if (activeAssigneeTab.value === 'awaiting') {
      localConversationList = awaitingChatsList.value;
    } else if (activeAssigneeTab.value === 'pending_closure') {
      localConversationList = pendingClosureChatsList.value;
    } else if (activeAssigneeTab.value === 'ai') {
      localConversationList = aiChatsList.value;
    } else {
      localConversationList = allChatList.value;
    }
  } else {
    localConversationList = chatLists.value;
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  if (
    !hasAppliedFiltersOrActiveFolders.value &&
    activeSortBy.value === wootConstants.SORT_BY_TYPE.UNREAD
  ) {
    localConversationList = sortByUnreadStatus(localConversationList);
  }

  return localConversationList;
});

const showEndOfListMessage = computed(() => {
  return !!(
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;
  // Prioritize conversationStatus prop from route over saved filter
  activeStatus.value =
    props.conversationStatus || status || wootConstants.STATUS_TYPE.OPEN;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    contacts: [getContact.value(folderContactId.value)],
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  appliedFilter.value = [];
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');
  // Force refresh tab counts when switching views/routes
  // The /meta endpoint is lightweight (counts only), safe to run in parallel
  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filtersForMeta = { ...conversationFilters.value };
    delete filtersForMeta.assigneeType;
    filtersForMeta.force = true;
    store.dispatch('conversationStats/get', filtersForMeta);
  }
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
}

function loadMoreConversations() {
  // Não carregar mais a lista normal enquanto a busca estiver ativa
  if (isSearchActive.value) {
    return;
  }
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

function updateAssigneeTab(selectedTab) {
  if (props.conversationType === 'unattended') {
    let query;
    if (selectedTab === wootConstants.ASSIGNEE_TYPE.UNASSIGNED) {
      query = { assignee_type: 'unassigned' };
    } else if (selectedTab === wootConstants.ASSIGNEE_TYPE.ALL) {
      query = { assignee_type: 'all' };
    }
    router.push({
      name: 'conversation_unattended',
      params: { accountId: currentAccountId.value },
      ...(query && { query }),
    });
    return;
  }
  // Unread: keep the active tab reflected in the URL (?assignee_type=...) for
  // all three tabs, so the address bar always matches the highlighted tab and
  // the view is deep-linkable. The deep-link watcher then syncs the tab state
  // and refetches. Always explicit (unlike unattended, whose default is "me").
  if (props.conversationType === 'unread') {
    const queryByTab = {
      [wootConstants.ASSIGNEE_TYPE.ME]: 'me',
      [wootConstants.ASSIGNEE_TYPE.UNASSIGNED]: 'unassigned',
      [wootConstants.ASSIGNEE_TYPE.ALL]: 'all',
    };
    router.push({
      name: 'conversation_unread',
      params: { accountId: currentAccountId.value },
      query: { assignee_type: queryByTab[selectedTab] ?? 'all' },
    });
    return;
  }
  if (activeAssigneeTab.value !== selectedTab) {
    resetBulkActions();
    emitter.emit('clearSearchInput');
    activeAssigneeTab.value = selectedTab;
    store.dispatch('conversationPage/reset');
    store.dispatch('emptyAllConversations');
    fetchConversations();
  }
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
  } else {
    activeSortBy.value = value;
  }
  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';
  if (isOnMentionsView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.MENTION;
  } else if (isOnParticipatingView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.PARTICIPATING;
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = wootConstants.CONVERSATION_TYPE.UNATTENDED;
  } else if (isOnUnreadView({ route: { name } })) {
    conversationType = 'unread';
  }
  router.push(
    conversationListPageURL({
      accountId,
      conversationType: conversationType,
      customViewId: props.foldersId,
      inboxId,
      label,
      teamId,
    })
  );
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

function leaveConversationIfAccessLost(team, conversationId) {
  // Conversation routes use either :conversation_id or :conversationId
  // depending on the view (conversation.routes.js).
  const openConversationId = Number(
    route.params.conversation_id ?? route.params.conversationId
  );
  if (!openConversationId || openConversationId !== Number(conversationId)) {
    return;
  }
  // An empty teams store right after a team assignment means it has not
  // loaded yet — fail open instead of ejecting a legitimate member.
  if (!teamsList.value.length) return;
  // assigneeId stays null: on a team change the backend clears or reassigns
  // a non-member assignee (ensure_assignee_is_from_team).
  const lostAccess = losesConversationAccess({
    isAdmin: currentRole.value === 'administrator',
    userId: currentUser.value.id,
    userTeamIds: myTeams.value.map(memberTeam => memberTeam.id),
    teamId: team.id,
    assigneeId: null,
  });
  if (lostAccess) {
    useAlert(t('CONVERSATION.ASSIGNMENT_ACCESS_LOST'));
    router.push(`/app/accounts/${currentAccountId.value}/dashboard`);
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
      rethrow: true,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
    leaveConversationIfAccessLost(team, conversationId);
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  // Check for required attributes before resolving
  const conversation = getConversationById.value(conversationId);

  // "Atribuição obrigatória": intercept non-assignee resolves with the dialog.
  if (requiresAssignmentToResolve(conversation)) {
    openAssignResolveDialog(conversation, snoozedUntil);
    return;
  }

  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    // Pass conversation context through the modal's API
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes =
      existingConversation?.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

function onOpenSearch() {
  showSearchModal.value = true;
}

function clearLocalSearchCache() {
  cachedSearchResults.value = [];
  cachedSearchQuery.value = '';
  store.dispatch('conversationSearch/clearSearchResults');
}

function onCloseSearch() {
  // Only clear if the modal was actually open (not triggered by Vue reactivity)
  if (showSearchModal.value) {
    showSearchModal.value = false;
    clearLocalSearchCache();
  }
}

function onSearch() {
  // Search is handled by ConversationSearchBar via store dispatch
}

function onClearSearch() {
  clearLocalSearchCache();
}

function onSelectSearchConversation(conversation) {
  const { accountId } = route.params;
  const { id } = conversation;

  // Navegar sem limpar resultados — usuário limpa manualmente com X ou Escape
  const url = conversationUrl({
    accountId,
    id,
    activeInbox: searchContext.value.inboxId,
    label: searchContext.value.label,
    teamId: searchContext.value.teamId,
    conversationType: searchContext.value.conversationType,
    foldersId: searchContext.value.foldersId,
  });

  router.push(frontendURL(url));
}

useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  const filtersForMeta = { ...conversationFilters.value };
  delete filtersForMeta.assigneeType;
  store.dispatch('conversationStats/get', filtersForMeta);
});

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
  // AI tab eligibility: failure is tolerated (empty records ⇒ no AI tab;
  // an account without Captain must not break the chat list)
  if (isAssignmentGateEnabled.value) {
    store.dispatch('captainAssistants/get').catch(() => {});
  }
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

// Unattended/Unread routes: sync assignee tab from route (deep-link).
watch(
  () => [route.name, route.query],
  () => {
    if (
      route.name === 'conversation_unattended' ||
      UNREAD_ROUTES.includes(route.name)
    ) {
      const newTab = resolveAssigneeTab(
        route.name,
        route.query,
        permittedAssigneeTabKeys.value
      );
      const prevTab = activeAssigneeTab.value;
      activeAssigneeTab.value = newTab;
      if (prevTab !== newTab) {
        store.dispatch('conversationPage/reset');
        store.dispatch('emptyAllConversations');
        fetchConversations();
      }
    }
  },
  { deep: true }
);

// Single watcher for all view-level changes that require a full re-fetch.
// Consolidates 6 separate watchers into 1, preventing duplicate API calls
// when multiple props change simultaneously (e.g., route navigation).
watch(
  [
    () => props.conversationStatus,
    () => props.conversationInbox,
    () => props.label,
    () => props.conversationType,
    activeTeam,
    activeFolder,
  ],
  (
    [newStatus, , , newType, , newFolder],
    [prevStatus, , , prevType, , prevFolder]
  ) => {
    // Side effect: sync status filter
    if (newStatus !== prevStatus) {
      if (newStatus) {
        activeStatus.value = newStatus;
        store.dispatch('setChatStatusFilter', newStatus);
      } else {
        const { conversations_filter_by: filterBy = {} } = uiSettings.value;
        const { status } = filterBy;
        activeStatus.value = status || wootConstants.STATUS_TYPE.OPEN;
        store.dispatch('setChatStatusFilter', activeStatus.value);
      }
    }

    // Side effect: reset assignee tab when the view type changes.
    // Use the route-aware default so the Unread view keeps its "All" default
    // and the dedicated unassigned queue locks to "Unassigned" instead of being
    // forced back to "Mine". Clamp by permission, not tab-bar visibility.
    if (newType !== prevType && newType !== 'unattended') {
      activeAssigneeTab.value = resolveAssigneeTab(
        route.name,
        route.query,
        permittedAssigneeTabKeys.value
      );
    }

    // Side effect: sync active folder in store
    if (newFolder !== prevFolder) {
      store.dispatch(
        'customViews/setActiveConversationFolder',
        newFolder || null
      );
    }

    resetAndFetchData();
  }
);

// Dynamic tabs (gate ON) can disappear while active when their count drops to
// zero — "Aguardando atendimento", "IA" e (legado) "Não atribuídas". Isso
// deixaria activeTabIndex em -1, então voltamos para "Minhas". Não se aplica à
// visão de não-respondidas (abas incondicionais lá).
watch(
  [
    () => conversationStats.value.unAssignedCount,
    () => conversationStats.value.awaitingCount,
    () => conversationStats.value.aiCount,
    isAssignmentGateEnabled,
  ],
  () => {
    if (props.conversationType === 'unattended') return;
    if (!isAssignmentGateEnabled.value) return;
    if (!conversationStats.value.updatedOn) return;

    const active = activeAssigneeTab.value;
    const countByTab = {
      [wootConstants.ASSIGNEE_TYPE.UNASSIGNED]:
        conversationStats.value.unAssignedCount,
      [wootConstants.ASSIGNEE_TYPE.AWAITING]:
        conversationStats.value.awaitingCount,
      [wootConstants.ASSIGNEE_TYPE.AI]: conversationStats.value.aiCount,
    };
    if (active in countByTab && (countByTab[active] ?? 0) === 0) {
      updateAssigneeTab(wootConstants.ASSIGNEE_TYPE.ME);
    }
  }
);

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, newVal => {
  store.dispatch('updateChatListFilters', newVal);
});
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1 relative"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[380px] 2xl:w-[448px]',
    ]"
  >
    <slot />
    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      :search-context="searchContext"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
      @open-search="onOpenSearch"
      @search="onSearch"
      @clear-search="onClearSearch"
    />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <ChatTypeTabs
      v-if="!hasAppliedFiltersOrActiveFolders && !isSearchActive"
      :items="assigneeTabItems"
      :active-tab="activeAssigneeTab"
      is-compact
      @chat-tab-change="updateAssigneeTab"
    />

    <p
      v-if="!chatListLoading && !conversationList.length && !isSearchActive"
      class="flex overflow-auto justify-center items-center p-4"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>
    <div
      v-else-if="showSearchNoResults"
      class="flex flex-col items-center justify-center p-8 overflow-auto text-center"
    >
      <div
        class="w-12 h-12 rounded-full bg-n-slate-3 dark:bg-n-solid-3 flex items-center justify-center mb-4"
      >
        <span class="i-lucide-search size-6 text-n-slate-11" />
      </div>
      <p class="text-base font-medium text-n-slate-12 mb-1">
        {{ $t('CONVERSATION.SEARCH.NO_RESULTS_TITLE') }}
      </p>
      <p class="text-sm text-n-slate-11 max-w-[280px]">
        {{
          conversationSearchQuery
            ? $t('CONVERSATION.SEARCH.NO_RESULTS_FOR_QUERY', {
                query: conversationSearchQuery,
              })
            : $t('CONVERSATION.SEARCH.NO_RESULTS')
        }}
      </p>
    </div>
    <ConversationBulkActions
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      :class="isOnExpandedLayout && 'sm:!w-[24rem] !w-full'"
      @select-all-conversations="toggleSelectAll"
    />
    <ConversationList
      :conversation-list="conversationList"
      :is-loading="
        isSearchActive
          ? store.getters['conversationSearch/getUIFlags']?.conversation
              ?.isFetching
          : chatListLoading
      "
      :show-end-of-list-message="showEndOfListMessage && !isSearchActive"
      :label="label"
      :team-id="teamId"
      :folders-id="foldersId"
      :conversation-type="conversationType"
      :conversation-status="conversationStatus"
      :show-assignee="showAssigneeInConversationCard"
      :is-on-expanded-layout="isOnExpandedLayout"
      @load-more="loadMoreConversations"
    />
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <ConversationSearchModal
      :is-open="showSearchModal"
      :context="searchContext"
      @close="onCloseSearch"
      @select-conversation="onSelectSearchConversation"
    />
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
    <AssignAndResolveDialog
      :show="showAssignResolveDialog"
      :variant="assignResolveContext.variant"
      :assignee-name="assignResolveContext.assigneeName"
      :requires-team="assignResolveContext.requiresTeam"
      :teams="myTeams"
      @confirm="handleAssignAndResolve"
      @close="closeAssignResolveDialog"
    />
  </div>
</template>
