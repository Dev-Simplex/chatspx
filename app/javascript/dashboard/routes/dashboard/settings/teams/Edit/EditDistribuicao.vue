<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

import TeamDistribuicaoFields from '../TeamDistribuicaoFields.vue';

// Casca de página do passo "Distribuição" do assistente do time. Toda a configuração vive no
// TeamDistribuicaoFields, que é o MESMO componente embutido na tela de edição do time — duplicar
// a tela recriaria o problema que a auditoria de 26/08 achou (duas telas editando a mesma tabela,
// nenhuma mostrando o que a outra configurou).
const route = useRoute();
const teamId = computed(() => route.params.teamId);
</script>

<template>
  <div class="h-full w-full p-8 col-span-6 overflow-auto">
    <TeamDistribuicaoFields :team-id="teamId" />
  </div>
</template>
