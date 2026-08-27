<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import WidgetHead from './WidgetHead.vue';
import WidgetBody from './WidgetBody.vue';
import WidgetPreChatPreview from './WidgetPreChatPreview.vue';
import WidgetFooter from './WidgetFooter.vue';
import WidgetTeaser from './WidgetTeaser.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Code from 'dashboard/components/Code.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { useBranding } from 'shared/composables/useBranding';
import { useMapGetter } from 'dashboard/composables/store';
import { brandTokens } from 'dashboard/routes/dashboard/settings/inbox/widget/composables/useContrast';

/**
 * O preview do widget.
 *
 * Duas coisas mudaram aqui, e as duas eram dividas medidas:
 *
 * **D4 — as ~74 custom properties literais.** Este arquivo carregava uma copia
 * da paleta do widget dentro do proprio `<style>`. Duas copias da mesma paleta
 * divergem sem ninguem perceber: quem muda o widget nao tem motivo para abrir o
 * preview. Agora a paleta vem dos MIXINS de
 * `widget/assets/scss/_tokens_values.scss` — o mesmo arquivo que pinta o widget
 * de verdade. Nao ha segunda copia para divergir.
 *
 * **O tema do preview era o tema do PAINEL.** O escuro vinha de
 * `.dark .widget-wrapper`, isto e, da classe que o dashboard poe no `<html>`:
 * o cliente nao conseguia ver o widget escuro sem trocar o proprio painel.
 * Agora o preview tem tema proprio, aplicado por classe no wrapper.
 *
 * E a cor da marca deixou de ser `background: props.color` cru: o preview
 * aplica os tokens DERIVADOS (`--w-brand`, `--w-on-brand`, `--w-brand-readable`,
 * `--w-focus-ring-color`), os mesmos que `WidgetTokens` emite no servidor. Era
 * o preview reproduzindo o proprio defeito que esta onda conserta — texto
 * branco sobre verde, 2,27:1.
 */
const props = defineProps({
  welcomeHeading: { type: String, default: '' },
  welcomeTagline: { type: String, default: '' },
  websiteName: { type: String, required: true },
  logo: { type: String, default: '' },
  isOnline: { type: Boolean, default: true },
  replyTime: { type: String, default: '' },
  color: { type: String, default: '' },
  widgetBubblePosition: { type: String, default: '' },
  widgetBubbleLauncherTitle: { type: String, default: '' },
  widgetBubbleType: { type: String, default: '' },
  webWidgetScript: { type: String, default: '' },
  /** Tema configurado na inbox: `light`, `dark` ou `auto`. */
  themeMode: { type: String, default: 'auto' },
  /** Distancia do lançador ate as bordas, em px (o default e o do servidor). */
  offsetX: { type: Number, default: 0 },
  offsetY: { type: Number, default: 0 },
  hideBubble: { type: Boolean, default: false },
  /**
   * Bloco 3.16 — o pré-chat como a tela 3 o configurou.
   *
   * Duas props, e nenhuma delas é cor: o preview do pré-chat pinta com os
   * mesmos tokens do resto (`--w-brand` / `--w-on-brand`). Sem isto, a única
   * forma de saber como o formulário ficou era salvar e abrir o site.
   */
  preChatEnabled: { type: Boolean, default: false },
  preChatOptions: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const globalConfig = useMapGetter('globalConfig/get');

const isChatMode = ref(false);
const [isWidgetVisible, toggleWidget] = useToggle(true);
const activeTabIndex = ref(0);

/**
 * `auto` no preview mostra o claro por padrao: o preview e uma maquete, e a
 * maquete precisa de um estado definido. Quem quiser ver o outro lado clica no
 * toggle — que e justamente o que nao existia.
 */
const previewTheme = ref(props.themeMode === 'dark' ? 'dark' : 'light');
watch(
  () => props.themeMode,
  mode => {
    previewTheme.value = mode === 'dark' ? 'dark' : 'light';
  }
);
const isDarkPreview = computed({
  get: () => previewTheme.value === 'dark',
  set: value => {
    previewTheme.value = value ? 'dark' : 'light';
  },
});

const isMobilePreview = ref(false);

const tabs = computed(() => [
  {
    label: t(
      'INBOX_MGMT.WIDGET_BUILDER.WIDGET_OPTIONS.WIDGET_VIEW_OPTION.PREVIEW'
    ),
  },
  {
    label: t(
      'INBOX_MGMT.WIDGET_BUILDER.WIDGET_OPTIONS.WIDGET_VIEW_OPTION.SCRIPT'
    ),
  },
]);

const isPreviewTab = computed(() => activeTabIndex.value === 0);

/**
 * O snippet que o cliente cola no site — **exatamente** como o servidor o
 * escreve (`Channel::WebWidget#web_widget_script`).
 *
 * O que existia aqui era o defeito D3: o script era cortado no byte 13
 * (`script.substring(0, 13)`) e no buraco entrava
 * `t('INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS')` — uma string de i18n cujo
 * conteúdo era JAVASCRIPT EXECUTÁVEL (`window.chatwootSettings = {options};`).
 * Duas consequências, e as duas chegavam ao site do cliente: um tradutor
 * mexendo numa chave de tradução quebrava o snippet de todo mundo naquele
 * idioma, e o corte por posição fixa quebrava sozinho se o servidor mudasse
 * um espaço no começo do script.
 *
 * As opções que aquele bloco injetava (posição, formato, texto do lançador)
 * não precisam mais viajar no snippet: elas moram em `widget_appearance` e o
 * servidor as entrega no boot. `chatwootSettings` continua funcionando no site
 * do cliente como OVERRIDE deliberado — e quando ele existe, a tela de
 * aparência avisa (3.09) em vez de mentir.
 */
const widgetScript = computed(() => props.webWidgetScript);

const replyTimeText = computed(() => {
  switch (props.replyTime) {
    case 'in_a_few_minutes':
      return t('INBOX_MGMT.WIDGET_BUILDER.REPLY_TIME.IN_A_FEW_MINUTES');
    case 'in_a_day':
      return t('INBOX_MGMT.WIDGET_BUILDER.REPLY_TIME.IN_A_DAY');
    default:
      return t('INBOX_MGMT.WIDGET_BUILDER.REPLY_TIME.IN_A_FEW_HOURS');
  }
});

const getWidgetConfig = computed(() => ({
  welcomeHeading: props.welcomeHeading,
  welcomeTagline: props.welcomeTagline,
  websiteName: props.websiteName,
  logo: props.logo,
  isDefaultScreen: !isChatMode.value,
  isOnline: props.isOnline,
  replyTime: replyTimeText.value,
}));

/** Os tokens que o servidor vai emitir para esta cor — nao a cor crua. */
const tokenStyle = computed(() => brandTokens(props.color || '#2dc46f'));

const themeClass = computed(() =>
  isDarkPreview.value ? 'wp-theme-dark' : 'wp-theme-light'
);

const surfaceWidth = computed(() =>
  isMobilePreview.value ? 'w-[22.5rem]' : 'w-80'
);

const getBubblePositionStyle = computed(() => ({
  justifyContent: props.widgetBubblePosition === 'left' ? 'start' : 'end',
  paddingInline: `${props.offsetX}px`,
  paddingBottom: `${props.offsetY}px`,
}));

const isBubbleExpanded = computed(
  () => !isWidgetVisible.value && props.widgetBubbleType === 'expanded_bubble'
);

const getWidgetBubbleLauncherTitle = computed(() =>
  isWidgetVisible.value || props.widgetBubbleType === 'standard'
    ? ' '
    : props.widgetBubbleLauncherTitle
);

const handleTabChange = tab => {
  activeTabIndex.value = tabs.value.findIndex(item => item.label === tab.label);
};

const handleToggleWidget = () => {
  toggleWidget();
  if (isWidgetVisible.value) {
    isChatMode.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-full min-h-0 flex-1">
    <!-- A barra transbordava: medido, scrollWidth 489 x clientWidth 416 em 1280
         (412 em 1440). Sem `flex-wrap` o navegador so tinha uma saida — espremer
         os rotulos — e "Modo do chat" virava 3 linhas de 39 px enquanto "Celular"
         era cortado em "Celu". `shrink-0` nos rotulos tira essa saida; o `wrap`
         da a segunda linha quando de fato nao cabe. -->
    <div
      class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 mb-6 flex-shrink-0"
    >
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="handleTabChange"
      />

      <div
        v-if="isPreviewTab"
        class="flex flex-wrap items-center gap-x-4 gap-y-2"
      >
        <div class="flex items-center gap-2">
          <span
            class="text-heading-3 text-n-slate-12 shrink-0 whitespace-nowrap"
          >
            {{ $t('INBOX_MGMT.WIDGET_BUILDER.WIDGET_SCREEN.CHAT') }}
          </span>
          <!-- O Switch e um <button role="switch">, nao um <input>: rotulo por
               `aria-label`, porque `<label for>` so amarra em controle nativo. -->
          <Switch
            v-model="isChatMode"
            :aria-label="$t('INBOX_MGMT.WIDGET_BUILDER.WIDGET_SCREEN.CHAT')"
            data-testid="preview-chat-toggle"
          />
        </div>
        <div class="flex items-center gap-2">
          <span
            class="text-heading-3 text-n-slate-12 shrink-0 whitespace-nowrap"
          >
            {{ $t('INBOX_WIDGET.PREVIEW.DARK') }}
          </span>
          <Switch
            v-model="isDarkPreview"
            :aria-label="$t('INBOX_WIDGET.PREVIEW.DARK')"
            data-testid="preview-theme-toggle"
          />
        </div>
        <div class="flex items-center gap-2">
          <span
            class="text-heading-3 text-n-slate-12 shrink-0 whitespace-nowrap"
          >
            {{ $t('INBOX_WIDGET.PREVIEW.MOBILE') }}
          </span>
          <Switch
            v-model="isMobilePreview"
            :aria-label="$t('INBOX_WIDGET.PREVIEW.MOBILE')"
            data-testid="preview-device-toggle"
          />
        </div>
      </div>
    </div>

    <div class="flex-1 min-h-0 flex flex-col">
      <div
        v-if="isPreviewTab"
        class="flex-1 flex flex-col items-center justify-end pb-4"
        :class="themeClass"
        :style="tokenStyle"
        data-testid="widget-preview-surface"
      >
        <div
          v-if="isWidgetVisible"
          class="widget-wrapper flex flex-1 flex-shrink-0 flex-col justify-between rounded-lg shadow-md bg-wp-surface h-[31.25rem] mb-4"
          :class="surfaceWidth"
        >
          <WidgetHead :config="getWidgetConfig" />
          <div>
            <!-- Na conversa, o visitante vê o pré-chat ANTES das mensagens —
                 é a ordem do widget real. Sem pré-chat, as bolhas de sempre. -->
            <WidgetPreChatPreview
              v-if="!getWidgetConfig.isDefaultScreen && preChatEnabled"
              :options="preChatOptions"
            />
            <WidgetBody v-else-if="!getWidgetConfig.isDefaultScreen" />
            <WidgetFooter :config="getWidgetConfig" />
            <div class="py-2.5 flex justify-center">
              <a
                class="flex items-center gap-0.5 cursor-pointer text-wp-text-muted text-xxs"
              >
                <img
                  class="max-w-2.5 max-h-2.5"
                  :src="globalConfig.logoThumbnail"
                  alt=""
                  aria-hidden="true"
                />
                <span>
                  {{
                    replaceInstallationName(
                      $t('INBOX_MGMT.WIDGET_BUILDER.BRANDING_TEXT')
                    )
                  }}
                </span>
              </a>
            </div>
          </div>
        </div>

        <div
          v-if="showTeaser && teaser"
          class="flex mb-2"
          :class="surfaceWidth"
          :style="getBubblePositionStyle"
        >
          <WidgetTeaser
            :level="teaser.level"
            :text="teaser.text"
            :sender-name="teaser.senderName"
            :avatar-url="teaser.avatarUrl"
            :intents="teaser.intents"
          />
        </div>

        <div
          v-if="!hideBubble"
          class="flex"
          :class="surfaceWidth"
          :style="getBubblePositionStyle"
        >
          <button
            class="relative flex items-center justify-center rounded-full cursor-pointer bg-w-brand text-w-on-brand"
            :class="
              isBubbleExpanded
                ? 'w-auto font-medium text-base h-12 px-4'
                : 'w-16 h-16'
            "
            data-testid="preview-launcher"
            :aria-label="
              isWidgetVisible
                ? $t('INBOX_WIDGET.PREVIEW.CLOSE_LAUNCHER')
                : $t('INBOX_WIDGET.PREVIEW.OPEN_LAUNCHER')
            "
            @click="handleToggleWidget"
          >
            <img
              v-if="!isWidgetVisible"
              src="~dashboard/assets/images/bubble-logo.svg"
              alt=""
              draggable="false"
              class="w-6 h-6 mx-auto"
            />
            <div v-if="isBubbleExpanded" class="ltr:pl-2.5 rtl:pr-2.5">
              {{ getWidgetBubbleLauncherTitle }}
            </div>
            <div v-if="isWidgetVisible" class="relative">
              <div
                class="absolute w-0.5 h-8 rotate-45 -translate-y-1/2 bg-current"
              />
              <div
                class="absolute w-0.5 h-8 -rotate-45 -translate-y-1/2 bg-current"
              />
            </div>
          </button>
        </div>
      </div>

      <div
        v-else
        class="flex-1 p-3 rounded-lg [&_code]:!bg-n-slate-2 bg-n-slate-2 min-w-0 overflow-auto [&_pre]:whitespace-pre-wrap [&_pre]:break-words [&_code]:whitespace-pre-wrap"
      >
        <Code
          :script="widgetScript"
          lang="html"
          class="!text-start"
          :codepen-title="`${websiteName} - Chatwoot Widget Test`"
          enable-code-pen
        />
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* A paleta do widget, sem uma segunda copia dela: os mixins vem do arquivo que
   pinta o widget de verdade. Aplicados em CLASSE — nunca em `:root` —, porque
   `:root` aqui sobrescreveria a paleta do dashboard inteiro, e porque e a
   classe que permite ao preview mostrar o tema OPOSTO ao do painel. */
@import '../../../../widget/assets/scss/tokens_values';

.wp-theme-light {
  @include widget-palette-light;
}

.wp-theme-dark {
  @include widget-palette-dark;
}
</style>
