<script setup>
// [TODO] This componet is too big and bulky to be in the same file, we can consider splitting this into multiple
// composables and components, useVirtualChatList, useChatlistFilters
import {
  ref,
  unref,
  provide,
  computed,
  watch,
  onMounted,
  defineEmits,
} from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

// [VITE] [TODO] We are using vue-virtual-scroll for now, since that seemed the simplest way to migrate
// from the current one. But we should consider using tanstack virtual in the future
// https://tanstack.com/virtual/latest/docs/framework/vue/examples/variable
import { DynamicScroller, DynamicScrollerItem } from 'vue-virtual-scroller';
import ChatListHeader from './ChatListHeader.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import ConversationItem from './ConversationItem.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeamSelectionModal from './widgets/conversation/TeamSelectionModal.vue';
import IntersectionObserver from './IntersectionObserver.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationSearchModal from './widgets/conversation/ConversationSearchModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useChatListKeyboardEvents } from 'dashboard/composables/chatlist/useChatListKeyboardEvents';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useEventListener } from '@vueuse/core';

import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import {
  conversationListPageURL,
  conversationUrl,
  frontendURL,
} from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';

import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';

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

const conversationListRef = ref(null);
const conversationDynamicScroller = ref(null);

provide('contextMenuElementTarget', conversationDynamicScroller);

const initialAssigneeTabFromRoute = () => {
  if (route.name === 'conversation_unattended') {
    if (route.query.assignee_type === 'unassigned')
      return wootConstants.ASSIGNEE_TYPE.UNASSIGNED;
    if (route.query.assignee_type === 'all')
      return wootConstants.ASSIGNEE_TYPE.ALL;
    return wootConstants.ASSIGNEE_TYPE.ME;
  }
  return wootConstants.ASSIGNEE_TYPE.ME;
};
const activeAssigneeTab = ref(initialAssigneeTabFromRoute());
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const isContextMenuOpen = ref(false);
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
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');

useChatListKeyboardEvents(conversationListRef);
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
  onAssignTeamsForBulk,
  onUpdateConversations,
  showTransferTeamModal,
  teams,
  onConfirmAgentTransferTeam,
  cancelAgentTransferTeamSelection,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

// computed
const intersectionObserverOptions = computed(() => {
  return {
    root: conversationListRef.value,
    rootMargin: '100px 0px 100px 0px',
  };
});

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
  const items = filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key }) => ({
    key,
    name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
    count: stats[countKeyForTab(key)] ?? 0,
  }));
  return items;
});

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
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
  const count = assigneeTabItems.value.find(
    item => item.key === activeAssigneeTab.value
  ).count;
  return count;
});

const conversationListPagination = computed(() => {
  const conversationsPerPage = 25;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
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
  if (props.conversationType === 'mention') {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (props.conversationType === 'participating') {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }
  if (props.conversationType === 'unattended') {
    return t('CHAT_LIST.UNATTENDED_HEADING');
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
    if (activeAssigneeTab.value === 'me') {
      localConversationList = mineChatsList.value;
    } else if (activeAssigneeTab.value === 'unassigned') {
      localConversationList = unAssignedChatsList.value;
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

  return localConversationList;
});

const showEndOfListMessage = computed(() => {
  return (
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
  // [VITE] removing this since the library has changed
  // nextTick(() => {
  //   // Addressing a known issue in the virtual list library where dynamically added items
  //   // might not render correctly. This workaround involves a slight manual adjustment
  //   // to the scroll position, triggering the list to refresh its rendering.
  //   const virtualList = conversationListRef.value;
  //   const scrollToOffset = virtualList?.scrollToOffset;
  //   const currentOffset = virtualList?.getOffset() || 0;
  //   if (scrollToOffset) {
  //     scrollToOffset(currentOffset + 1);
  //   }
  // });
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

// Add a method to handle scroll events
function handleScroll() {
  const scroller = conversationDynamicScroller.value;
  if (scroller && scroller.hasScrollbar) {
    const { scrollTop, scrollHeight, clientHeight } = scroller.$el;
    if (scrollHeight - (scrollTop + clientHeight) < 100) {
      loadMoreConversations();
    }
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
    conversationType = 'mention';
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = 'unattended';
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

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
    router.push(`/app/accounts/${currentAccountId.value}/dashboard`);
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(conversationId, status, snoozedUntil) {
  store
    .dispatch('toggleStatus', {
      conversationId,
      status,
      snoozedUntil,
    })
    .then(() => {
      useAlert(t('CONVERSATION.CHANGE_STATUS'));
    });
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return store.getters.getConversationById(item)?.status === status;
  });
}

function onContextMenuToggle(state) {
  isContextMenuOpen.value = state;
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

useEventListener(conversationDynamicScroller, 'scroll', handleScroll);

onMounted(() => {
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
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
provide('updateConversationStatus', toggleConversationStatus);
provide('toggleContextMenu', onContextMenuToggle);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

// Unattended route: sync assignee tab from query params
watch(
  () => [route.name, route.query],
  () => {
    if (route.name === 'conversation_unattended') {
      const qt = route.query.assignee_type;
      let newTab = wootConstants.ASSIGNEE_TYPE.ME;
      if (qt === 'unassigned') {
        newTab = wootConstants.ASSIGNEE_TYPE.UNASSIGNED;
      } else if (qt === 'all') {
        newTab = wootConstants.ASSIGNEE_TYPE.ALL;
      }
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

    // Side effect: reset assignee tab when leaving unattended view
    if (newType !== prevType && newType !== 'unattended') {
      activeAssigneeTab.value = wootConstants.ASSIGNEE_TYPE.ME;
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

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

watch(conversationFilters, newVal => {
  store.dispatch('updateChatListFilters', newVal);
});
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 bg-n-solid-1 conversations-list-wrap"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[340px] 2xl:w-[412px]',
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
      class="flex items-center justify-center p-4 overflow-auto"
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
        <fluent-icon icon="search" size="24" class="text-n-slate-11" />
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
      v-if="selectedConversations.length"
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      @select-all-conversations="toggleSelectAll"
      @assign-agent="onAssignAgent"
      @update-conversations="onUpdateConversations"
      @assign-labels="onAssignLabels"
      @assign-team="onAssignTeamsForBulk"
    />
    <TeamSelectionModal
      :show="showTransferTeamModal"
      :teams="teams"
      :title="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE')"
      :description="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_DESCRIPTION')"
      @confirm="onConfirmAgentTransferTeam"
      @close="cancelAgentTransferTeamSelection"
    />
    <div
      ref="conversationListRef"
      class="flex-1 overflow-hidden conversations-list hover:overflow-y-auto"
      :class="{ 'overflow-hidden': isContextMenuOpen }"
    >
      <DynamicScroller
        ref="conversationDynamicScroller"
        :items="conversationList"
        :min-item-size="24"
        class="w-full h-full overflow-auto"
      >
        <template #default="{ item, index, active }">
          <!--
            If we encounter resizing issues, we can set the `watchData` prop to true
            this will deeply watch the entire object instead of just size dependencies
            But it can impact performance
          -->
          <DynamicScrollerItem
            :item="item"
            :active="active"
            :data-index="index"
            :size-dependencies="[
              item.labels,
              item.sla_policy_id,
              item.priority,
            ]"
          >
            <ConversationItem
              :key="`conversation-${item.id}`"
              :source="item"
              :label="label"
              :team-id="teamId"
              :folders-id="foldersId"
              :conversation-type="conversationType"
              :conversation-status="conversationStatus"
              :show-assignee="showAssigneeInConversationCard"
              @select-conversation="selectConversation"
              @de-select-conversation="deSelectConversation"
            />
          </DynamicScrollerItem>
        </template>
        <template #after>
          <div
            v-if="
              (isSearchActive &&
                store.getters['conversationSearch/getUIFlags']?.conversation
                  ?.isFetching) ||
              (!isSearchActive && chatListLoading)
            "
            class="flex justify-center my-4"
          >
            <Spinner class="text-n-brand" />
          </div>
          <p
            v-else-if="showEndOfListMessage && !isSearchActive"
            class="p-4 text-center text-n-slate-11"
          >
            {{ $t('CHAT_LIST.EOF') }}
          </p>
          <IntersectionObserver
            v-else
            :options="intersectionObserverOptions"
            @observed="loadMoreConversations"
          />
        </template>
      </DynamicScroller>
    </div>
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
  </div>
</template>
