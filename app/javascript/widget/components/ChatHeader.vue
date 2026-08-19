<script setup>
import { computed, toRef } from 'vue';
import { useRouter } from 'vue-router';
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
const { isOnline } = useAvailability(availableAgents);

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};

const atendidoPorIA = computed(() => props.attendant === ATTENDANT.AI);
const atendidoPorHumano = computed(() => props.attendant === ATTENDANT.HUMAN);
</script>

<template>
  <header class="flex justify-between w-full p-5 bg-w-brand gap-2">
    <div class="flex items-center">
      <button
        v-if="showBackButton"
        class="px-2 ltr:-ml-3 rtl:-mr-3"
        @click="onBackButtonClick"
      >
        <FluentIcon icon="chevron-left" size="24" class="text-white" />
      </button>
      <img
        v-if="avatarUrl"
        class="w-8 h-8 ltr:mr-3 rtl:ml-3 rounded-full"
        :src="avatarUrl"
        :alt="$t('A11Y.AGENT_AVATAR')"
      />
      <div class="flex flex-col gap-1">
        <div
          class="flex items-center text-base font-medium leading-4 text-white"
        >
          <span v-dompurify-html="title" class="ltr:mr-1 rtl:ml-1" />
          <div
            :class="`h-2 w-2 rounded-full
              ${isOnline ? 'bg-white/80' : 'hidden'}`"
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
        <AvailabilityContainer
          :agents="availableAgents"
          :show-header="false"
          :show-avatars="false"
          text-classes="text-xs leading-3 text-white/80"
        />
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
