<script>
import { mapGetters } from 'vuex';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import WahaConnectionsBanner from './components/app/WahaConnectionsBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import vueActionCable from './helper/actionCable';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import WootSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFontSize } from 'dashboard/composables/useFontSize';
import {
  registerSubscription,
  verifyServiceWorkerExistence,
} from './helper/pushHelper';
import ReconnectService from 'dashboard/helper/ReconnectService';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAutoUpdate } from 'dashboard/composables/useAutoUpdate';
import { useDocumentTitle } from 'dashboard/composables/useDocumentTitle';
import AppVersionBanner from './components/app/AppVersionBanner.vue';
import MessageToast from './components-next/notifications/MessageToast.vue';
import OnboardingChecklist from './components-next/Onboarding/OnboardingChecklist.vue';
import PwaInstallPrompt from './components-next/PwaInstallPrompt/PwaInstallPrompt.vue';
import PushPermissionPrompt from './components-next/PushPermissionPrompt/PushPermissionPrompt.vue';

export default {
  name: 'App',

  components: {
    LoadingState,
    NetworkNotification,
    UpdateBanner,
    AppVersionBanner,
    WahaConnectionsBanner,
    PaymentPendingBanner,
    WootSnackbarBox,
    PendingEmailVerificationBanner,
    MessageToast,
    OnboardingChecklist,
    PwaInstallPrompt,
    PushPermissionPrompt,
  },
  setup() {
    const router = useRouter();
    const store = useStore();
    const { accountId } = useAccount();
    // Use the font size composable (it automatically sets up the watcher)
    const { currentFontSize } = useFontSize();
    const { uiSettings } = useUISettings();
    useAutoUpdate();
    useDocumentTitle();

    return {
      router,
      store,
      currentAccountId: accountId,
      currentFontSize,
      uiSettings,
    };
  },
  data() {
    return {
      latestChatwootVersion: null,
      maintenanceBanner: null,
      updateBanner: null,
      actionCableConnector: null,
      reconnectService: null,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      isRTL: 'accounts/isRTL',
      currentUser: 'getCurrentUser',
      authUIFlags: 'getAuthUIFlags',
      accountUIFlags: 'accounts/getUIFlags',
    }),
    hideOnOnboardingView() {
      return !isOnOnboardingView(this.$route);
    },
  },

  watch: {
    currentAccountId: {
      immediate: true,
      handler() {
        if (this.currentAccountId) {
          this.initializeAccount();
        }
      },
    },
  },
  mounted() {
    this.initializeColorTheme();
    this.listenToThemeChanges();
    // If user locale is set, use it; otherwise use account locale
    this.setLocale(
      this.uiSettings?.locale || window.chatwootConfig.selectedLocale
    );
  },
  unmounted() {
    if (this.reconnectService) {
      this.reconnectService.disconnect();
      this.reconnectService = null;
    }
    if (this.actionCableConnector) {
      this.actionCableConnector.disconnect();
      this.actionCableConnector = null;
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.onchange = e => setColorTheme(e.matches);
    },
    setLocale(locale) {
      this.$root.$i18n.locale = locale;
    },
    async initializeAccount() {
      if (this.reconnectService) {
        this.reconnectService.disconnect();
        this.reconnectService = null;
      }
      if (this.actionCableConnector) {
        this.actionCableConnector.disconnect();
        this.actionCableConnector = null;
      }

      await this.$store.dispatch('accounts/get');
      this.$store.dispatch('setActiveAccount', {
        accountId: this.currentAccountId,
      });
      const {
        locale,
        latest_chatwoot_version: latestChatwootVersion,
        maintenance_banner: maintenanceBanner,
        update_banner: updateBanner,
      } = this.getAccount(this.currentAccountId);
      const { pubsub_token: pubsubToken } = this.currentUser || {};
      // If user locale is set, use it; otherwise use account locale
      this.setLocale(this.uiSettings?.locale || locale);
      this.latestChatwootVersion = latestChatwootVersion;
      this.maintenanceBanner = maintenanceBanner;
      this.updateBanner = updateBanner;
      this.actionCableConnector = vueActionCable.init(this.store, pubsubToken);
      this.reconnectService = new ReconnectService(this.store, this.router);
      window.reconnectService = this.reconnectService;

      verifyServiceWorkerExistence(registration =>
        registration.pushManager.getSubscription().then(subscription => {
          if (subscription) {
            registerSubscription();
          }
        })
      );
    },
  },
};
</script>

<template>
  <div
    v-if="!authUIFlags.isFetching && !accountUIFlags.isFetchingItem"
    id="app"
    class="flex flex-col w-full h-screen min-h-0 bg-n-background"
    :dir="isRTL ? 'rtl' : 'ltr'"
  >
    <AppVersionBanner />
    <UpdateBanner
      :latest-chatwoot-version="latestChatwootVersion"
      :maintenance-banner="maintenanceBanner"
      :update-banner="updateBanner"
    />
    <template v-if="currentAccountId">
      <WahaConnectionsBanner />
      <PendingEmailVerificationBanner v-if="hideOnOnboardingView" />
      <PaymentPendingBanner v-if="hideOnOnboardingView" />
    </template>
    <router-view v-slot="{ Component }">
      <transition name="fade" mode="out-in">
        <component :is="Component" />
      </transition>
    </router-view>
    <WootSnackbarBox />
    <NetworkNotification />
    <MessageToast />
    <OnboardingChecklist v-if="currentAccountId" />
    <PwaInstallPrompt v-if="currentAccountId" />
    <PushPermissionPrompt v-if="currentAccountId" />
  </div>
  <LoadingState v-else />
</template>

<style lang="scss">
@import './assets/scss/app';

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}

.multiselect__input {
  margin-bottom: 0px !important;
}
</style>

<style src="vue-multiselect/dist/vue-multiselect.css"></style>
