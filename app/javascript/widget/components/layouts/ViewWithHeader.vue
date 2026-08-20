<script>
import Banner from '../Banner.vue';
import Branding from 'shared/components/Branding.vue';
import ChatHeader from '../ChatHeader.vue';
import ChatHeaderExpanded from '../ChatHeaderExpanded.vue';
import configMixin from '../../mixins/configMixin';
import { mapGetters } from 'vuex';
import { currentAttendant } from 'widget/helpers/aiIdentity';
import { IFrameHelper } from 'widget/helpers/utils';

export default {
  components: {
    Banner,
    Branding,
    ChatHeader,
    ChatHeaderExpanded,
  },
  mixins: [configMixin],
  data() {
    return {
      showPopoutButton: false,
      scrollPosition: 0,
      ticking: true,
      disableBranding: window.chatwootWebChannel.disableBranding || false,
      requestID: null,
    };
  },
  computed: {
    ...mapGetters({
      appConfig: 'appConfig/getAppConfig',
      availableAgents: 'agent/availableAgents',
      conversation: 'conversation/getConversation',
      isWidgetOpen: 'appConfig/getIsWidgetOpen',
    }),
    /**
     * Bloco 4.09 — quem atende AGORA, para o rotulo persistente do cabecalho.
     *
     * Resolvido AQUI e passado pronto: o cabecalho nao sabe ler mensagem, e nao
     * deve passar a saber.
     *
     * `getConversation` devolve um objeto indexado por `message.id`
     * (`conversation/mutations.js:70`). A ordem de `Object.values` sobre chave
     * INTEIRA e numerica ascendente, nao de insercao — e e por isso que isto
     * funciona: carregar mensagens antigas insere ids MENORES depois, e ainda
     * assim a lista sai cronologica. Depender de ordem de insercao daria o
     * atendente errado no header logo apos rolar para tras.
     */
    currentAttendant() {
      return currentAttendant(Object.values(this.conversation || {}));
    },
    portal() {
      return window.chatwootWebChannel.portal;
    },
    isHeaderCollapsed() {
      if (!this.hasIntroText) {
        return true;
      }
      return !this.isOnHomeView;
    },
    hasIntroText() {
      return (
        this.channelConfig.welcomeTitle || this.channelConfig.welcomeTagline
      );
    },
    showBackButton() {
      return ['article-viewer', 'messages', 'prechat-form'].includes(
        this.$route.name
      );
    },
    isOnArticleViewer() {
      return ['article-viewer'].includes(this.$route.name);
    },
    isOnHomeView() {
      return ['home'].includes(this.$route.name);
    },
    opacityClass() {
      if (this.isHeaderCollapsed) {
        return {};
      }
      if (this.scrollPosition > 30) {
        return { 'opacity-30': true };
      }
      if (this.scrollPosition > 25) {
        return { 'opacity-40': true };
      }
      if (this.scrollPosition > 20) {
        return { 'opacity-60': true };
      }
      if (this.scrollPosition > 15) {
        return { 'opacity-80': true };
      }
      if (this.scrollPosition > 10) {
        return { 'opacity-90': true };
      }
      return {};
    },
  },
  watch: {
    /**
     * Aceite 6 do bloco 2.05, a metade que NAO e do composer.
     *
     * Na view de mensagens quem toma o foco e o campo — `useComposer` cuida
     * disso, e essa logica JA existia (a §C.9 alerta que reimplementar
     * duplicaria). Na tela inicial nao ha campo: o composer nem esta montado. O
     * foco vai para o `h1` do cabecalho, que por isso ganhou `tabindex="-1"` no
     * bloco 2.06.
     *
     * E o motivo de nao focar um campo aqui e concreto: em celular, focar campo
     * abre o teclado virtual e come metade da tela antes de o visitante ter lido
     * qualquer coisa.
     */
    isWidgetOpen(aberto) {
      if (!aberto || !this.isOnHomeView) return;
      this.$nextTick(() => this.$el?.querySelector('h1')?.focus());
    },
  },
  mounted() {
    this.$el.addEventListener('scroll', this.updateScrollPosition);
  },
  unmounted() {
    this.$el.removeEventListener('scroll', this.updateScrollPosition);
    cancelAnimationFrame(this.requestID);
  },
  methods: {
    closeWindow() {
      IFrameHelper.sendMessage({ event: 'closeWindow' });
    },
    updateScrollPosition(event) {
      this.scrollPosition = event.target.scrollTop;
      if (!this.ticking) {
        this.requestID = window.requestAnimationFrame(() => {
          this.ticking = false;
        });

        this.ticking = true;
      }
    },
  },
};
</script>

<template>
  <div
    class="w-full h-full bg-n-slate-2 dark:bg-n-solid-1"
    :class="{ 'overflow-auto': isOnHomeView }"
    @keydown.esc="closeWindow"
  >
    <div class="relative flex flex-col h-full">
      <div
        :class="{
          expanded: !isHeaderCollapsed,
          collapsed: isHeaderCollapsed,
          'shadow-[0_10px_15px_-16px_rgba(50,50,93,0.08),0_4px_6px_-8px_rgba(50,50,93,0.04)]':
            isHeaderCollapsed,
          ...opacityClass,
        }"
      >
        <ChatHeaderExpanded
          v-if="!isHeaderCollapsed"
          :intro-heading="appConfig.welcomeTitle || channelConfig.welcomeTitle"
          :intro-body="
            appConfig.welcomeDescription || channelConfig.welcomeTagline
          "
          :avatar-url="channelConfig.avatarUrl"
          :show-popout-button="appConfig.showPopoutButton"
        />
        <ChatHeader
          v-if="isHeaderCollapsed"
          :title="channelConfig.websiteName"
          :avatar-url="channelConfig.avatarUrl"
          :show-popout-button="appConfig.showPopoutButton"
          :available-agents="availableAgents"
          :attendant="currentAttendant"
          :show-back-button="showBackButton"
        />
      </div>
      <Banner />
      <!-- A regiao principal da tela. Sem ela, quem navega por leitor de tela
           nao tem para onde pular: o widget e um documento inteiro dentro de um
           iframe, e o cabecalho e o rodape ja sao landmarks. -->
      <main class="flex flex-col flex-1 min-h-0">
        <router-view />
      </main>

      <Branding v-if="!isOnArticleViewer" :disable-branding="disableBranding" />
    </div>
  </div>
</template>
