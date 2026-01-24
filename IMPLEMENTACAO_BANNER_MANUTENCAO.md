# Implementação do Banner de Manutenção

Este documento contém todas as alterações necessárias para implementar o sistema de banner de manutenção com animação Lottie no Chatwoot.

## 📋 Resumo Executivo

**Arquivos criados:**
- `lib/maintenance_banner.rb` (novo)
- `UpdateBanner.vue.COMPLETO` (referência para cópia)

**Arquivos modificados:**
1. `lib/redis/redis_keys.rb` - Adicionar constante MAINTENANCE_BANNER
2. `app/controllers/api/v1/accounts_controller.rb` - Adicionar busca de maintenance_banner
3. `app/views/api/v1/accounts/show.json.jbuilder` - Adicionar maintenance_banner no JSON
4. `app/javascript/dashboard/App.vue` - Adicionar prop maintenanceBanner
5. `app/javascript/dashboard/components/app/UpdateBanner.vue` - **SUBSTITUIR COMPLETO**
6. `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json` - Adicionar traduções

**Dependências:**
- `@lottiefiles/dotlottie-vue` (instalar via pnpm)

**Arquivo de animação:**
- Copiar `Under Maintenance.lottie` para `public/assets/`

## Índice
1. [Dependências](#dependências)
2. [Arquivos Novos](#arquivos-novos)
3. [Arquivos Modificados](#arquivos-modificados)
4. [Arquivo de Animação](#arquivo-de-animação)
5. [Comandos Rails Console](#comandos-rails-console)

---

## Dependências

### Frontend
Instalar a dependência do LottieFiles:

```bash
cd /home/chatwoot/chatwoot
pnpm add @lottiefiles/dotlottie-vue
```

---

## Arquivos Novos

### 1. `/home/chatwoot/chatwoot/lib/maintenance_banner.rb`

Criar este arquivo com o seguinte conteúdo:

```ruby
# frozen_string_literal: true

class MaintenanceBanner
  include Redis::RedisKeys

  class << self
    def enable(message, scheduled_at = nil)
      data = {
        enabled: true,
        message: message.to_s,
        scheduled_at: scheduled_at ? parse_scheduled_at(scheduled_at) : nil
      }.compact

      Redis::Alfred.set(Redis::RedisKeys::MAINTENANCE_BANNER, data.to_json)
      data
    end

    def disable
      Redis::Alfred.delete(Redis::RedisKeys::MAINTENANCE_BANNER)
      { enabled: false }
    end

    def active?
      info[:enabled] == true
    end

    def info
      json_data = Redis::Alfred.get(Redis::RedisKeys::MAINTENANCE_BANNER)
      return { enabled: false } if json_data.blank?

      parsed_data = JSON.parse(json_data)
      {
        enabled: parsed_data['enabled'] || false,
        message: parsed_data['message'] || '',
        scheduled_at: parsed_data['scheduled_at']
      }
    rescue JSON::ParserError, StandardError => e
      Rails.logger.error("Erro ao buscar banner de manutenção: #{e.message}") if defined?(Rails)
      { enabled: false }
    end

    private

    def parse_scheduled_at(scheduled_at)
      return nil if scheduled_at.blank?

      time = case scheduled_at
             when String
               Time.zone.parse(scheduled_at) || Time.parse(scheduled_at)
             when Time, DateTime
               scheduled_at
             else
               nil
             end

      time&.utc&.iso8601
    end
  end
end
```

---

## Arquivos Modificados

### 2. `/home/chatwoot/chatwoot/lib/redis/redis_keys.rb`

**Adicionar** a seguinte linha após `LATEST_CHATWOOT_VERSION`:

```ruby
MAINTENANCE_BANNER = 'MAINTENANCE_BANNER'.freeze
```

**Localização exata:**
```ruby
CHATWOOT_INSTALLATION_ONBOARDING = 'CHATWOOT_INSTALLATION_ONBOARDING'.freeze
CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING = 'CHATWOOT_CONFIG_RESET_WARNING'.freeze
LATEST_CHATWOOT_VERSION = 'LATEST_CHATWOOT_VERSION'.freeze
MAINTENANCE_BANNER = 'MAINTENANCE_BANNER'.freeze  # <-- ADICIONAR ESTA LINHA
```

### 3. `/home/chatwoot/chatwoot/app/controllers/api/v1/accounts_controller.rb`

**Modificar** o método `show`:

**ANTES:**
```ruby
def show
  @latest_chatwoot_version = ::Redis::Alfred.get(::Redis::Alfred::LATEST_CHATWOOT_VERSION)
  render 'api/v1/accounts/show', format: :json
end
```

**DEPOIS:**
```ruby
def show
  @latest_chatwoot_version = ::Redis::Alfred.get(::Redis::Alfred::LATEST_CHATWOOT_VERSION)
  @maintenance_banner = begin
    MaintenanceBanner.info
  rescue StandardError => e
    Rails.logger.error("Erro ao buscar banner de manutenção: #{e.message}")
    { enabled: false }
  end
  render 'api/v1/accounts/show', format: :json
end
```

### 4. `/home/chatwoot/chatwoot/app/views/api/v1/accounts/show.json.jbuilder`

**Adicionar** a seguinte linha após `json.latest_chatwoot_version`:

```ruby
json.partial! 'api/v1/models/account', formats: [:json], resource: @account
json.latest_chatwoot_version @latest_chatwoot_version
json.maintenance_banner @maintenance_banner || { enabled: false }  # <-- ADICIONAR ESTA LINHA
json.partial! 'enterprise/api/v1/accounts/partials/account', account: @account if ChatwootApp.enterprise?
```

### 5. `/home/chatwoot/chatwoot/app/javascript/dashboard/App.vue`

**Modificar** a propriedade `data()`:

**ANTES:**
```javascript
data() {
  return {
    showAddAccountModal: false,
    latestChatwootVersion: null,
    reconnectService: null,
  };
},
```

**DEPOIS:**
```javascript
data() {
  return {
    showAddAccountModal: false,
    latestChatwootVersion: null,
    maintenanceBanner: null,
    reconnectService: null,
  };
},
```

**Modificar** o método `initializeAccount()`:

**ANTES:**
```javascript
const { locale, latest_chatwoot_version: latestChatwootVersion } =
  this.getAccount(this.currentAccountId);
const { pubsub_token: pubsubToken } = this.currentUser || {};
this.setLocale(locale);
this.latestChatwootVersion = latestChatwootVersion;
```

**DEPOIS:**
```javascript
const {
  locale,
  latest_chatwoot_version: latestChatwootVersion,
  maintenance_banner: maintenanceBanner,
} = this.getAccount(this.currentAccountId);
const { pubsub_token: pubsubToken } = this.currentUser || {};
this.setLocale(locale);
this.latestChatwootVersion = latestChatwootVersion;
this.maintenanceBanner = maintenanceBanner;
```

**Modificar** o template para passar a prop:

**ANTES:**
```vue
<UpdateBanner :latest-chatwoot-version="latestChatwootVersion" />
```

**DEPOIS:**
```vue
<UpdateBanner
  :latest-chatwoot-version="latestChatwootVersion"
  :maintenance-banner="maintenanceBanner"
/>
```

### 6. `/home/chatwoot/chatwoot/app/javascript/dashboard/components/app/UpdateBanner.vue`

**SUBSTITUIR** o arquivo completo pelo conteúdo do arquivo `UpdateBanner.vue.COMPLETO` que está na raiz do projeto.

**OU** copie o conteúdo completo abaixo (312 linhas):

```vue
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
```

### 7. `/home/chatwoot/chatwoot/app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json`

**Adicionar** as seguintes linhas após `UPDATE_CHATWOOT`:

```json
"UPDATE_CHATWOOT": "Uma atualização {latestChatwootVersion} para o Chatwoot está disponível. Por favor, atualize sua instância.",
"MAINTENANCE_BANNER": "Sistema em manutenção",
"MAINTENANCE_SCHEDULED": "Manutenção programada para {scheduledAt}",
"LEARN_MORE": "Saiba mais",
```

---

## Arquivo de Animação

### 8. Copiar arquivo de animação

Copiar o arquivo `Under Maintenance.lottie` para:

```bash
cp /home/chatwoot/Under\ Maintenance.lottie /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie
```

**OU** se o arquivo já estiver em `/home/chatwoot/chatwoot`:

```bash
cp /home/chatwoot/chatwoot/Under\ Maintenance.lottie /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie
```

Verificar se o arquivo foi copiado:

```bash
ls -lh /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie
```

---

## Comandos Rails Console

### Ativar Banner de Manutenção

```ruby
# Ativar com mensagem e data/hora
MaintenanceBanner.enable("Sistema em manutenção", "2024-01-15 20:00:00")

# Ativar apenas com mensagem (sem data/hora)
MaintenanceBanner.enable("Sistema em manutenção")

# Verificar status
MaintenanceBanner.active?

# Ver informações completas
MaintenanceBanner.info

# Desativar
MaintenanceBanner.disable
```

---

## Resumo das Alterações

### Arquivos Criados:
1. `lib/maintenance_banner.rb`

### Arquivos Modificados:
1. `lib/redis/redis_keys.rb` - Adicionada constante MAINTENANCE_BANNER
2. `app/controllers/api/v1/accounts_controller.rb` - Adicionada busca de maintenance_banner
3. `app/views/api/v1/accounts/show.json.jbuilder` - Adicionado maintenance_banner na resposta JSON
4. `app/javascript/dashboard/App.vue` - Adicionada prop maintenanceBanner e passagem para UpdateBanner
5. `app/javascript/dashboard/components/app/UpdateBanner.vue` - Reescrito completamente
6. `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json` - Adicionadas traduções

### Dependências:
- `@lottiefiles/dotlottie-vue` (instalar via pnpm)

### Arquivos de Assets:
- `public/assets/Under Maintenance.lottie` (copiar manualmente)

---

## Ordem de Execução Recomendada

1. Instalar dependência: `pnpm add @lottiefiles/dotlottie-vue`
2. Criar arquivo `lib/maintenance_banner.rb`
3. Modificar `lib/redis/redis_keys.rb`
4. Modificar `app/controllers/api/v1/accounts_controller.rb`
5. Modificar `app/views/api/v1/accounts/show.json.jbuilder`
6. Modificar `app/javascript/dashboard/App.vue`
7. Substituir `app/javascript/dashboard/components/app/UpdateBanner.vue`
8. Modificar `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json`
9. Copiar arquivo de animação para `public/assets/`
10. Reiniciar servidor Rails e recompilar assets (se necessário)

---

## Notas Importantes

- O banner de atualização do Chatwoot foi **desabilitado permanentemente**
- Apenas o banner de manutenção será exibido quando ativado via Rails console
- A animação Lottie fica ao lado do texto, centralizada no banner
- O sistema é totalmente funcional e não quebra outras funcionalidades

