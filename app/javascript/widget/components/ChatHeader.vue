<script setup>
import { toRef } from 'vue';
import { useRouter } from 'vue-router';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import HeaderActions from './HeaderActions.vue';
import AvailabilityContainer from 'widget/components/Availability/AvailabilityContainer.vue';
import { useAvailability } from 'widget/composables/useAvailability';

const props = defineProps({
  avatarUrl: { type: String, default: '' },
  title: { type: String, default: '' },
  showPopoutButton: { type: Boolean, default: false },
  showBackButton: { type: Boolean, default: false },
  availableAgents: { type: Array, default: () => [] },
});

const availableAgents = toRef(props, 'availableAgents');

const router = useRouter();
const { isOnline } = useAvailability(availableAgents);

const onBackButtonClick = () => {
  router.replace({ name: 'home' });
};
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
          <!-- Cor sozinha nao informa nada (SC 1.4.1): o ponto tem nome
               acessivel, e ele muda com o estado em vez de sumir. -->
          <div
            role="img"
            data-testid="availability-dot"
            :aria-label="
              isOnline
                ? $t('TEAM_AVAILABILITY.ONLINE')
                : $t('TEAM_AVAILABILITY.OFFLINE')
            "
            class="h-2 w-2 rounded-full bg-w-on-brand"
            :class="isOnline ? 'opacity-80' : 'opacity-40'"
          />
        </div>
        <AvailabilityContainer
          :agents="availableAgents"
          :show-header="false"
          :show-avatars="false"
          text-classes="text-xs leading-3 text-w-on-brand opacity-80"
        />
      </div>
    </div>
    <HeaderActions :show-popout-button="showPopoutButton" />
  </header>
</template>
