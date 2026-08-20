<script setup>
import HeaderActions from './HeaderActions.vue';
import { computed } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  avatarUrl: {
    type: String,
    default: '',
  },
  introHeading: {
    type: String,
    default: '',
  },
  introBody: {
    type: String,
    default: '',
  },
  showPopoutButton: {
    type: Boolean,
    default: false,
  },
});

const { formatMessage } = useMessageFormatter();

const containerClasses = computed(() => [
  props.avatarUrl ? 'justify-between' : 'justify-end',
]);
</script>

<template>
  <header
    class="header-expanded min-h-24 pt-6 pb-4 px-5 relative box-border w-full bg-w-brand"
  >
    <div class="flex items-start" :class="containerClasses">
      <img
        v-if="avatarUrl"
        class="h-12 rounded-md"
        :src="avatarUrl"
        :alt="$t('A11Y.AGENT_AVATAR')"
      />
      <HeaderActions
        :show-popout-button="showPopoutButton"
        :show-end-conversation-button="false"
      />
    </div>
    <!-- `h1`, e nao `h2`: na tela inicial este e o titulo da pagina, e o
         cabecalho colapsado (que tem o seu proprio `h1`) nunca coexiste com
         este — os dois sao `v-if` mutuamente exclusivos em ViewWithHeader. -->
    <h1
      v-dompurify-html="introHeading"
      class="mt-4 text-2xl mb-1.5 font-medium text-w-on-brand line-clamp-4"
      tabindex="-1"
    />
    <p
      v-dompurify-html="formatMessage(introBody)"
      class="text-lg leading-normal text-w-on-brand opacity-80 [&_a]:underline line-clamp-6"
    />
  </header>
</template>
