<script>
import PreChatBody from './PreChatBody.vue';

/**
 * CASCA (bloco 3.15). Eram 570 linhas: estado, máscara, etapa, validação e a
 * marcação de cada campo, tudo dentro do arquivo que o upstream reescreve a cada
 * minor (R15 mediu +39/−33 de conflito por versão). O aceite exige menos de 60.
 *
 * Para onde foi cada parte:
 *   · a REGRA (show_if, etapa, máscara, validação) → `widget/helpers/preChatFieldRules.js`
 *   · o ESTADO do formulário                       → `widget/composables/usePreChatForm.js`
 *   · a marcação de UM campo                       → `widget/ui/WField.vue`
 *   · a marcação do formulário                     → `./PreChatBody.vue`
 *
 * Aqui sobra o que casca deve ter: delegação. Um conflito de merge neste arquivo
 * passa a caber numa linha.
 *
 * `components:` explícito, e não `<script setup>`: o guarda do bloco 2.18
 * (`widget/specs/formKitSobDemanda.spec.js`) caminha a árvore de `components`
 * para provar que o FormKit só aparece na rota do pré-chat, e `<script setup>`
 * não expõe essa árvore — a casca ficaria opaca e o guarda cego.
 */
export default {
  name: 'PreChatForm',
  components: { PreChatBody },
  props: {
    options: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['submitPreChat'],
};
</script>

<template>
  <PreChatBody
    :options="options"
    @submit-pre-chat="$emit('submitPreChat', $event)"
  />
</template>
