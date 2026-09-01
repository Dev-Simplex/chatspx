<script setup>
import { computed, toRef } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import HeaderActions from './HeaderActions.vue';
import AvailabilityContainer from 'widget/components/Availability/AvailabilityContainer.vue';
import { useAvailability } from 'widget/composables/useAvailability';
import { ATTENDANT } from 'widget/helpers/aiIdentity';

const props = defineProps({
  avatarUrl: { type: String, default: '' },
  title: { type: String, default: '' },
  showPopoutButton: { type: Boolean, default: false },
  showBackButton: { type: Boolean, default: false },
  availableAgents: { type: Array, default: () => [] },
  // Bloco 4.09 — a 2a das tres marcacoes: quem atende AGORA, persistente.
  // Vem resolvido de fora (`ATTENDANT` de `helpers/aiIdentity`); o cabecalho nao
  // sabe ler mensagem, e nao deve passar a saber.
  attendant: { type: String, default: ATTENDANT.UNKNOWN },
});

const availableAgents = toRef(props, 'availableAgents');

const router = useRouter();
const { t } = useI18n();
const { isOnline } = useAvailability(availableAgents);

const availableMessage = useMapGetter('appConfig/getAvailableMessage');
const unavailableMessage = useMapGetter('appConfig/getUnavailableMessage');

/**
 * Bloco 2.06, a 6a entrega da linha: "status com rotulo textual".
 *
 * TEXTUAL quer dizer VISIVEL. A entrega anterior pagou o item com `role="img"`
 * + `aria-label` no ponto, e nome acessivel so existe para leitor de tela: quem
 * enxerga ficava com duas opacidades da MESMA cor para distinguir (deltaE 7,9
 * em deuteranopia), que e cor sozinha comunicando estado — SC 1.4.1.
 *
 * Deriva de `isOnline`, a MESMA fonte que pinta o ponto. Ter uma fonte so e o
 * ponto inteiro: o `AvailabilityContainer` decide o cabecalho DELE por
 * `isOnline || (horario habilitado E dentro dele)`, que e mais largo, e por isso
 * o `show-header` continua desligado abaixo — ligado, ele escreveria
 * "conectados" ao lado de um ponto apagado sempre que o horario estivesse
 * aberto sem ninguem conectado. O `header.spec.js` mede essa divergencia.
 *
 * A mensagem configurada pelo cliente vem primeiro; a chave traduzida e o
 * fallback, e existe nos 56 locales.
 */
const statusLabel = computed(() =>
  isOnline.value
    ? availableMessage.value || t('TEAM_AVAILABILITY.ONLINE')
    : unavailableMessage.value || t('TEAM_AVAILABILITY.OFFLINE')
);

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};

const atendidoPorIA = computed(() => props.attendant === ATTENDANT.AI);
const atendidoPorHumano = computed(() => props.attendant === ATTENDANT.HUMAN);
</script>

<template>
  <!-- 56 px de piso (bloco 2.06). `min-h`, e nao `h`: nome de site longo pode
       quebrar em duas linhas, e altura fixa cortaria o titulo do cliente. -->
  <header
    class="flex justify-between w-full min-h-14 px-4 py-2 bg-w-brand gap-2 items-center"
  >
    <div class="flex items-center">
      <!-- 44x44 ate 768 px e 40x40 acima: o alvo de toque do celular manda no
           piso (SC 2.5.8), e o ponteiro do desktop nao precisa dele. -->
      <button
        v-if="showBackButton"
        class="flex items-center justify-center min-w-11 min-h-11 md:min-w-10 md:min-h-10 ltr:-ml-2 rtl:-mr-2"
        :aria-label="$t('A11Y.BACK')"
        @click="onBackButtonClick"
      >
        <FluentIcon icon="chevron-left" size="24" class="text-w-on-brand" />
      </button>
      <img
        v-if="avatarUrl"
        class="w-8 h-8 ltr:mr-3 rtl:ml-3 rounded-md"
        :src="avatarUrl"
        :alt="$t('A11Y.AGENT_AVATAR')"
      />
      <div class="flex flex-col gap-1">
        <div
          data-testid="header-title-row"
          class="flex items-center gap-1 text-base font-medium leading-4 text-w-on-brand"
        >
          <!-- O unico `h1` desta tela. O bloco 2.05 leva o foco para ca quando o
               widget abre numa tela de leitura, em vez de abrir o teclado do
               celular na cara do visitante. -->
          <h1
            v-dompurify-html="title"
            class="m-0 text-base font-medium leading-4"
            tabindex="-1"
          />
        </div>
        <!--
          Bloco 4.09 — rotulo PERSISTENTE de quem atende.

          A cor sai de `--w-on-brand`, que o servidor calcula por luminancia
          (bloco 1.02): o cabecalho e pintado com a cor da marca, e cravar branco
          aqui deixaria o rotulo ilegivel em toda inbox de marca clara.

          Duas chaves LITERAIS em vez de uma interpolada, pelo mesmo motivo do
          marcador: chave montada em runtime o lint nao confere.
        -->
        <span
          v-if="atendidoPorIA"
          class="chat-header__atendente"
          data-attendant="ai"
        >
          {{ $t('AI_IDENTITY.HEADER_AI') }}
        </span>
        <span
          v-else-if="atendidoPorHumano"
          class="chat-header__atendente"
          data-attendant="human"
        >
          {{ $t('AI_IDENTITY.HEADER_HUMAN') }}
        </span>
        <!--
          A linha de estado. O ponto e o rotulo ficam JUNTOS e saem da MESMA
          fonte (`isOnline`), entao nao ha estado em que um diga o contrario do
          outro. Depois deles vem o tempo de resposta, que e outro fato: o
          rotulo diz SE tem alguem, o `AvailabilityContainer` diz em QUANTO
          tempo respondem.

          `flex-wrap`: o widget embutido tem 400 px de largura e as duas
          mensagens sao configuraveis pelo cliente — sem isso, texto longo
          estoura a caixa em vez de quebrar.
        -->
        <div
          data-testid="header-status-row"
          class="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-xs leading-3 text-w-on-brand"
        >
          <!-- Decoracao: quem carrega o estado agora e o texto ao lado. Com
               `role="img"` + `aria-label` aqui, o leitor de tela anunciaria o
               mesmo estado duas vezes seguidas. -->
          <div
            data-testid="availability-dot"
            aria-hidden="true"
            class="h-2 w-2 rounded-full shrink-0 bg-w-on-brand"
            :class="isOnline ? 'opacity-80' : 'opacity-40'"
          />
          <span data-testid="availability-label" class="opacity-90">
            {{ statusLabel }}
          </span>
          <AvailabilityContainer
            :agents="availableAgents"
            :show-header="false"
            :show-avatars="false"
            text-classes="text-xs leading-3 text-w-on-brand opacity-80"
          />
        </div>
      </div>
    </div>
    <HeaderActions :show-popout-button="showPopoutButton" />
  </header>
</template>

<style scoped lang="scss">
.chat-header__atendente {
  // `--w-on-brand` e a decisao de contraste que o servidor ja tomou sobre a cor
  // da marca. Cravar branco aqui quebraria o cabecalho de toda inbox que nao usa
  // o verde padrao — que e exatamente o defeito que o bloco 1.02 existe para
  // matar. O fallback so vale para aba aberta antes do deploy dele.
  color: var(--w-on-brand, #ffffff);
  @apply text-xs leading-3 opacity-90;
}
</style>
