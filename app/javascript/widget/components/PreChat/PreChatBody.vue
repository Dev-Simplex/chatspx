<script>
import { computed } from 'vue';
import CustomButton from 'shared/components/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import { FormKit } from '@formkit/vue';
import WField from 'widget/ui/WField.vue';
import { usePreChatForm } from 'widget/composables/usePreChatForm';

/**
 * O CORPO DO PRÉ-CHAT — bloco 3.15.
 *
 * `PreChat/Form.vue` é o arquivo que o upstream reescreve a cada minor (R15), e
 * o aceite exige casca de menos de 60 linhas nele. Este arquivo é novo, então
 * não colide com nada: é aqui que o formulário mora, e lá sobra a delegação.
 *
 * O estado está em `usePreChatForm`; cada campo é um `WField`. O que ficou neste
 * componente é só a decisão de O QUE mostrar — cabeçalho, campos da etapa, o
 * campo de mensagem e qual dos dois botões.
 *
 * `setup()` devolve o composable inteiro para o proxy da instância: é o que
 * mantém `formValues`, `onSubmit` e companhia alcançáveis pelo mesmo nome que
 * tinham quando viviam em `data()`/`methods`.
 */
export default {
  components: { CustomButton, Spinner, FormKit, WField },
  props: {
    options: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['submitPreChat'],
  setup(props, { emit }) {
    return usePreChatForm({
      options: computed(() => props.options),
      emit,
    });
  },
};
</script>

<template>
  <!-- O botão de submit do FormKit fica escondido: quem envia é o `CustomButton`
       abaixo, que também é o botão de avançar quando há mais de uma etapa. -->
  <FormKit
    v-model="formValues"
    type="form"
    form-class="flex flex-col flex-1 w-full p-6 overflow-y-auto"
    :incomplete-message="false"
    :submit-attrs="{ inputClass: 'hidden', wrapperClass: 'hidden' }"
    @submit="onSubmit"
  >
    <div
      v-if="shouldShowHeaderMessage"
      v-dompurify-html="headerMessageHtml"
      class="mb-4 text-base leading-5 text-n-slate-12 [&>p>.link]:text-w-brand-readable [&>p>.link]:hover:underline"
    />
    <WField
      v-for="item in fieldsOfCurrentStep"
      :key="item.name"
      :field="item"
      :label="item.label"
      :errors="delegatedErrors(item)"
      @blur="markTouched"
    />
    <!-- A mensagem é o que ABRE a conversa: pedir texto livre na etapa 1 de um
         formulário de 2 etapas inverte a ordem — responde-se antes de saber o
         que ainda vem. Por isso ela só entra na última etapa. -->
    <FormKit
      v-if="!hasActiveCampaign && isLastStep"
      name="message"
      type="textarea"
      label-class="text-sm font-medium text-n-slate-12"
      input-class="mt-1 rounded w-full py-2 px-3"
      :label="$t('PRE_CHAT_FORM.FIELDS.MESSAGE.LABEL')"
      :placeholder="$t('PRE_CHAT_FORM.FIELDS.MESSAGE.PLACEHOLDER')"
      validation="required"
      :validation-messages="{
        required: $t('PRE_CHAT_FORM.FIELDS.MESSAGE.ERROR'),
      }"
    />

    <!-- Com etapas, o botão avança em vez de enviar até a última. `type="button"`
         é o que impede o FormKit de submeter o formulário antes de o visitante
         ter visto os campos das etapas seguintes. -->
    <CustomButton
      v-if="hasMultipleSteps && !isLastStep"
      class="mt-3 mb-5 font-medium flex items-center justify-center gap-2"
      block
      type="button"
      @click="goToNextStep"
    >
      {{ $t('PRE_CHAT_FORM.CONTINUE') }}
    </CustomButton>
    <CustomButton
      v-else
      class="mt-3 mb-5 font-medium flex items-center justify-center gap-2"
      block
      :disabled="isCreatingConversation"
    >
      <Spinner v-if="isCreatingConversation" class="p-0" />
      {{ $t('START_CONVERSATION') }}
    </CustomButton>
  </FormKit>
</template>
