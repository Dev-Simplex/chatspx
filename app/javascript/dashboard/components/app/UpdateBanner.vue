<script>
import { DotLottieVue } from '@lottiefiles/dotlottie-vue';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { LocalStorage } from 'shared/helpers/localStorage';
import { mapGetters } from 'vuex';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { hasAnUpdateAvailable } from './versionCheckHelper';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';

export default {
  components: {
    DotLottieVue,
  },
  props: {
    latestChatwootVersion: { type: String, default: '' },
    maintenanceBanner: {
      type: Object,
      default: () => null,
    },
  },
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      userDismissedBanner: false,
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    updateAvailable() {
      return hasAnUpdateAvailable(
        this.latestChatwootVersion,
        this.globalConfig.appVersion
      );
    },
    maintenanceActive() {
      return this.maintenanceBanner && this.maintenanceBanner.enabled === true;
    },
    bannerMessage() {
      if (this.maintenanceActive) {
        let message =
          this.maintenanceBanner.message ||
          this.$t('GENERAL_SETTINGS.MAINTENANCE_BANNER');

        if (this.maintenanceBanner.scheduled_at) {
          try {
            const scheduledDate = new Date(this.maintenanceBanner.scheduled_at);
            const formattedDate = format(
              scheduledDate,
              "dd/MM/yyyy 'às' HH:mm",
              {
                locale: ptBR,
              }
            );
            message += ` - ${this.$t('GENERAL_SETTINGS.MAINTENANCE_SCHEDULED', {
              scheduledAt: formattedDate,
            })}`;
          } catch (e) {
            // Se houver erro ao formatar data, apenas mostra a mensagem
          }
        }

        return message;
      }

      return this.$t('GENERAL_SETTINGS.UPDATE_CHATWOOT', {
        latestChatwootVersion: this.latestChatwootVersion,
      });
    },
    shouldShowBanner() {
      // Prioridade para banner de manutenção
      if (this.maintenanceActive) {
        return !this.userDismissedBanner && this.isAdmin;
      }

      // Banner de atualização desabilitado permanentemente
      return false;
    },
    colorScheme() {
      return this.maintenanceActive ? 'warning' : 'primary';
    },
  },
  methods: {
    isVersionNotificationDismissed(version) {
      const dismissedVersions =
        LocalStorage.get(LOCAL_STORAGE_KEYS.DISMISSED_UPDATES) || [];
      return dismissedVersions.includes(version);
    },
    dismissUpdateBanner() {
      if (this.maintenanceActive) {
        // Para manutenção, apenas esconde localmente
        this.userDismissedBanner = true;
      } else {
        // Para atualização, salva no localStorage
        let updatedDismissedItems =
          LocalStorage.get(LOCAL_STORAGE_KEYS.DISMISSED_UPDATES) || [];
        if (updatedDismissedItems instanceof Array) {
          updatedDismissedItems.push(this.latestChatwootVersion);
        } else {
          updatedDismissedItems = [this.latestChatwootVersion];
        }
        LocalStorage.set(
          LOCAL_STORAGE_KEYS.DISMISSED_UPDATES,
          updatedDismissedItems
        );
        this.userDismissedBanner = true;
      }
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="shouldShowBanner" class="maintenance-banner-wrapper">
    <div
      class="flex items-center h-12 px-4 py-3 text-xs text-white banner dark:text-white woot-banner"
      :class="[
        colorScheme,
        { 'gap-4': !maintenanceActive, 'gap-0': maintenanceActive },
      ]"
    >
      <div class="banner-content-wrapper">
        <!-- Animação Lottie ao lado do texto (apenas para manutenção) -->
        <div v-if="maintenanceActive" class="lottie-animation-container">
          <DotLottieVue
            src="/assets/Under Maintenance.lottie"
            autoplay
            loop
            class="lottie-player"
          />
        </div>
        <span class="banner-message">
          {{ bannerMessage }}
          <a
            v-if="!maintenanceActive && latestChatwootVersion"
            href="https://github.com/chatwoot/chatwoot/releases"
            rel="noopener noreferrer nofollow"
            target="_blank"
          >
            {{ $t('GENERAL_SETTINGS.LEARN_MORE') }}
          </a>
        </span>
      </div>

      <div class="actions">
        <button
          type="button"
          class="close-button"
          :aria-label="$t('GENERAL_SETTINGS.DISMISS')"
          @click="dismissUpdateBanner"
        >
          <i class="i-lucide-circle-x" />
        </button>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.maintenance-banner-wrapper {
  width: 100%;

  .banner {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;

    &.primary {
      @apply bg-n-brand;
    }

    &.warning {
      @apply bg-n-amber-5 text-n-amber-12;
    }

    .banner-content-wrapper {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-wrap: nowrap;
      margin: 0 auto;
      gap: 0 !important;
      padding: 0 !important;
      font-size: 0; /* Remove espaçamento entre elementos inline */
    }

    .lottie-animation-container {
      width: 150px;
      height: 48px;
      min-width: 150px;
      max-width: 150px;
      flex-shrink: 0;
      display: inline-block;
      align-items: center;
      justify-content: center;
      vertical-align: middle;
      margin-right: -20px !important;
      margin-left: 0 !important;
      padding-right: 0 !important;
      padding-left: 0 !important;
      font-size: 0;

      .lottie-player {
        width: 150px !important;
        height: 48px !important;
        max-width: 150px !important;
        max-height: 48px !important;
        margin: 0 !important;
        padding: 0 !important;
      }

      :deep(canvas),
      :deep(svg) {
        width: 150px !important;
        height: 48px !important;
        max-width: 150px !important;
        max-height: 48px !important;
        margin: 0 !important;
        padding: 0 !important;
      }
    }

    .banner-message {
      display: inline-block;
      align-items: center;
      white-space: nowrap;
      vertical-align: middle;
      margin-left: -20px !important;
      margin-right: 0 !important;
      padding-left: 0 !important;
      padding-right: 0 !important;
      font-size: 12px; /* Restaura o tamanho da fonte */
    }

    .actions {
      @apply flex gap-1;
      flex-shrink: 0;
      position: absolute;
      right: 16px;
    }

    .close-button {
      @apply flex items-center justify-center;
      @apply text-white dark:text-white;
      @apply hover:opacity-80;
      @apply transition-opacity;
      background: transparent;
      border: none;
      cursor: pointer;
      padding: 4px;

      i {
        font-size: 16px;
      }
    }

    a {
      @apply ml-1 underline text-xs;
    }

    &.warning a {
      @apply text-n-amber-12;
    }

    &.primary a {
      @apply text-white;
    }
  }
}

@media (max-width: 640px) {
  .maintenance-banner-wrapper {
    .banner {
      .lottie-animation-container {
        width: 120px;
        height: 40px;
        min-width: 120px;
        max-width: 120px;
        margin-right: 12px;

        .lottie-player {
          width: 120px !important;
          height: 40px !important;
          max-width: 120px !important;
          max-height: 40px !important;
        }

        :deep(svg),
        :deep(canvas) {
          width: 120px !important;
          height: 40px !important;
          max-width: 120px !important;
          max-height: 40px !important;
        }
      }

      .banner-message {
        font-size: 11px;
      }
    }
  }
}
</style>
