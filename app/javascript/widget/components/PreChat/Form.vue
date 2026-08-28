<script>
import CustomButton from 'shared/components/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import { mapGetters } from 'vuex';
import { isEmptyObject } from 'widget/helpers/utils';
import { getRegexp } from 'shared/helpers/Validators';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import configMixin from 'widget/mixins/configMixin';
import { FormKit, createInput } from '@formkit/vue';
import PhoneInput from 'widget/components/Form/PhoneInput.vue';
import { getRequiredMessage as buildRequiredMessage } from 'widget/helpers/preChatFieldMessages';
import { savePartialLead } from 'widget/api/partialLead';
// Bloco 3.15. TODA a regra de show_if / step / mask / validator mora no helper;
// este componente continua sendo casca. Ver o contrato em
// `widget/helpers/preChatFieldRules.js`.
import {
  fieldErrorFor,
  fieldsForStep,
  maskFieldValue,
  stepsOf,
  visibleFields,
} from 'widget/helpers/preChatFieldRules';

export default {
  components: {
    CustomButton,
    Spinner,
    FormKit,
  },
  mixins: [configMixin],
  props: {
    options: {
      type: Object,
      default: () => {},
    },
  },
  emits: ['submitPreChat'],
  setup() {
    const phoneInput = createInput(PhoneInput, {
      props: ['hasErrorInPhoneInput'],
    });
    const { formatMessage } = useMessageFormatter();

    return { formatMessage, phoneInput };
  },
  data() {
    return {
      locale: this.$root.$i18n.locale,
      hasErrorInPhoneInput: false,
      // Bloco 4.18 — temporizador do rascunho do lead incompleto. Instância, não módulo:
      // dois pré-chats montados (widget e campanha) não podem cancelar o rascunho um do
      // outro.
      partialLeadTimer: null,
      partialLeadSent: '',
      message: '',
      formValues: {},
      // Bloco 3.15 — etapa corrente e campos já visitados. `touchedFields` existe
      // porque erro de formato tem de aparecer no BLUR: acusar "CPF inválido" no
      // terceiro dígito é ruído, não ajuda.
      currentStep: 1,
      touchedFields: [],
      labels: {
        emailAddress: 'EMAIL_ADDRESS',
        fullName: 'FULL_NAME',
        phoneNumber: 'PHONE_NUMBER',
      },
    };
  },
  computed: {
    ...mapGetters({
      isCreating: 'conversation/getIsCreating',
      isConversationRouting: 'appConfig/getIsUpdatingRoute',
      activeCampaign: 'campaign/getActiveCampaign',
      currentUser: 'contacts/getCurrentUser',
    }),
    isCreatingConversation() {
      return this.isCreating || this.isConversationRouting;
    },
    hasActiveCampaign() {
      return !isEmptyObject(this.activeCampaign);
    },
    shouldShowHeaderMessage() {
      return (
        this.hasActiveCampaign ||
        (this.preChatFormEnabled && !!this.headerMessage)
      );
    },
    headerMessage() {
      if (this.preChatFormEnabled) {
        return this.options.preChatMessage;
      }
      if (this.hasActiveCampaign) {
        return this.$t('PRE_CHAT_FORM.CAMPAIGN_HEADER');
      }
      return '';
    },
    preChatFields() {
      return this.preChatFormEnabled ? this.options.preChatFields : [];
    },
    filteredPreChatFields() {
      const isUserEmailAvailable = this.currentUser.has_email;
      const isUserPhoneNumberAvailable = this.currentUser.has_phone_number;
      const isUserIdentifierAvailable = !!this.currentUser.identifier;

      const isUserNameAvailable = !!(
        isUserIdentifierAvailable ||
        isUserEmailAvailable ||
        isUserPhoneNumberAvailable
      );
      return this.preChatFields.filter(field => {
        if (isUserEmailAvailable && field.name === 'emailAddress') {
          return false;
        }
        if (isUserPhoneNumberAvailable && field.name === 'phoneNumber') {
          return false;
        }
        if (isUserNameAvailable && field.name === 'fullName') {
          return false;
        }
        return true;
      });
    },
    enabledPreChatFields() {
      // Bloco 3.15, e é a linha que carrega o bloco: filtrar AQUI faz o `show_if`
      // valer para tudo que deriva daqui — o que renderiza, o que é validado, o
      // que é enviado e o que conta para o rascunho de lead. Campo escondido não
      // existe para nenhum deles, que é a única leitura coerente de "escondido".
      return visibleFields(
        this.filteredPreChatFields.filter(field => field.enabled),
        this.formValues
      ).map(field => ({
        ...field,
        type:
          field.name === 'phoneNumber'
            ? this.phoneInput
            : this.findFieldType(field.type),
      }));
    },
    // Bloco 3.15 — as etapas ocupadas, já depois do `show_if`: um condicional
    // escondido não pode criar etapa vazia.
    visibleSteps() {
      return stepsOf(this.enabledPreChatFields);
    },
    fieldsOfCurrentStep() {
      return fieldsForStep(this.enabledPreChatFields, this.currentStep);
    },
    isLastStep() {
      const steps = this.visibleSteps;
      return this.currentStep >= steps[steps.length - 1];
    },
    hasMultipleSteps() {
      return this.visibleSteps.length > 1;
    },
    conversationCustomAttributes() {
      let conversationAttributes = {};
      this.enabledPreChatFields.forEach(field => {
        if (field.field_type === 'conversation_attribute') {
          conversationAttributes = {
            ...conversationAttributes,
            [field.name]: this.getValue(field),
          };
        }
      });
      return conversationAttributes;
    },
    contactCustomAttributes() {
      let contactAttributes = {};
      this.enabledPreChatFields.forEach(field => {
        if (field.field_type === 'contact_attribute') {
          contactAttributes = {
            ...contactAttributes,
            [field.name]: this.getValue(field),
          };
        }
      });
      return contactAttributes;
    },
  },
  watch: {
    formValues: {
      deep: true,
      handler() {
        this.applyFieldMasks();
        this.schedulePartialLead();
      },
    },
    // O `show_if` pode esconder a etapa em que estamos (o gatilho mudou de
    // resposta). Sem isto o visitante fica numa etapa que já não tem campo.
    visibleSteps() {
      if (!this.visibleSteps.includes(this.currentStep)) {
        this.currentStep = this.visibleSteps[0] ?? 1;
      }
    },
  },
  beforeUnmount() {
    clearTimeout(this.partialLeadTimer);
  },
  methods: {
    inputClass(input) {
      const { state, family: classification, type } = input.context;
      if (classification === 'box' && type === 'checkbox') {
        return '';
      }
      if (type === 'phoneInput') {
        this.hasErrorInPhoneInput = state.invalid;
      }
      return 'mt-1 rounded w-full py-2 px-3';
    },
    isContactFieldRequired(field) {
      return this.preChatFields.find(option => option.name === field).required;
    },
    getLabel({ label }) {
      return label;
    },
    getPlaceHolder({ placeholder }) {
      return placeholder;
    },
    // Bloco 2.17. A mensagem de obrigatoriedade deixa de ser a mesma palavra
    // para todos os campos e passa a nomear o campo — ver o contrato em
    // `widget/helpers/preChatFieldMessages.js`.
    getRequiredMessage(field) {
      return buildRequiredMessage({ field, t: this.$t });
    },
    getValue({ name, type }) {
      if (type === 'select') {
        return this.enabledPreChatFields.find(option => option.name === name)
          .values[this.formValues[name]];
      }
      return this.formValues[name] || null;
    },
    getValidation({ type, name, field_type, regex_pattern }) {
      const regex = regex_pattern ? getRegexp(regex_pattern) : null;
      // FormKit caches the RegExp and calls .test() across keystrokes, so
      // drop stateful g/y flags to stop lastIndex mutation flipping validity.
      const matchRegex = regex
        ? new RegExp(regex.source, regex.flags.replace(/[gy]/g, ''))
        : null;
      const validations = {
        emailAddress: 'email',
        phoneNumber: ['startsWithPlus', 'isValidPhoneNumber'],
        url: 'url',
        date: 'date',
        text: null,
        select: null,
        number: null,
        checkbox: false,
        contact_attribute: matchRegex ? [['matches', matchRegex]] : null,
        conversation_attribute: matchRegex ? [['matches', matchRegex]] : null,
      };
      const validationKeys = Object.keys(validations);
      const isRequired = this.isContactFieldRequired(name);
      const baseRules = isRequired ? [['required']] : [['optional']];

      if (
        !validationKeys.includes(name) &&
        !validationKeys.includes(type) &&
        !validationKeys.includes(field_type)
      ) {
        return '';
      }

      const validationType =
        validations[type] || validations[name] || validations[field_type];
      if (!validationType) return baseRules;

      // Normalise into array-of-arrays so RegExp objects in `['matches', regex]`
      // survive without being stringified by FormKit.
      const extraRules = Array.isArray(validationType)
        ? validationType.map(rule => (Array.isArray(rule) ? rule : [rule]))
        : [[validationType]];

      return baseRules.concat(extraRules);
    },
    findFieldType(type) {
      if (type === 'link') {
        return 'url';
      }
      if (type === 'list') {
        return 'select';
      }

      return type;
    },
    getOptions(item) {
      if (item.type === 'select') {
        let values = {};
        item.values.forEach((value, index) => {
          values = {
            ...values,
            [index]: value,
          };
        });
        return values;
      }
      return {};
    },
    /**
     * Bloco 4.18 — LEAD INCOMPLETO.
     *
     * A cada campo respondido, o rascunho vai para o servidor ANTES de existir conversa.
     * Sem isto, quem preenche nome e e-mail e fecha a aba no terceiro campo some sem
     * deixar rastro — que é exatamente o buraco que o bloco fecha.
     *
     * Espera 1,2 s de silêncio para não mandar uma requisição por tecla, e não repete um
     * rascunho idêntico ao último enviado. Se a captura estiver desligada na conta, o
     * servidor simplesmente não grava — o widget não conhece essa configuração e não deve.
     */
    schedulePartialLead() {
      clearTimeout(this.partialLeadTimer);
      this.partialLeadTimer = setTimeout(() => this.sendPartialLead(), 1200);
    },
    sendPartialLead() {
      const answers = this.filledAnswers();
      if (!Object.keys(answers).length) return;

      const payload = JSON.stringify(answers);
      if (payload === this.partialLeadSent) return;
      this.partialLeadSent = payload;

      const { step, stepKey } = this.stoppedAt(answers);
      savePartialLead({ answers, step, stepKey });
    },
    filledAnswers() {
      const answers = {};
      this.enabledPreChatFields.forEach(field => {
        const value = this.formValues[field.name];
        if (String(value ?? '').trim() !== '') answers[field.name] = value;
      });
      return answers;
    },
    /**
     * A ETAPA EM QUE PAROU é o primeiro campo habilitado ainda vazio — é essa a resposta
     * que o relatório precisa para dizer ONDE se perde o lead. Com tudo preenchido, a
     * etapa é a última: a pessoa chegou ao fim e ainda assim não enviou.
     */
    stoppedAt(answers) {
      const fields = this.enabledPreChatFields;
      const index = fields.findIndex(field => !(field.name in answers));
      return index === -1
        ? { step: fields.length, stepKey: fields[fields.length - 1]?.name }
        : { step: index + 1, stepKey: fields[index].name };
    },
    /**
     * Bloco 3.15 — máscara enquanto digita, delegada ao helper do 3.13.
     *
     * Roda no watcher que já existia, e é reentrante de propósito: reescrever
     * `formValues` dispara o watcher outra vez, mas a segunda passada devolve o
     * mesmo texto e a recursão para na comparação. Máscara desconhecida devolve o
     * valor intacto — máscara que não existe não pode comer o que foi digitado.
     */
    applyFieldMasks() {
      this.enabledPreChatFields.forEach(field => {
        const atual = this.formValues[field.name];
        if (typeof atual !== 'string' || !atual) return;
        const mascarado = maskFieldValue(atual, field);
        if (mascarado !== atual) this.formValues[field.name] = mascarado;
      });
    },
    markTouched(name) {
      if (!this.touchedFields.includes(name)) this.touchedFields.push(name);
    },
    /**
     * Bloco 3.15 — o erro ESPECÍFICO do campo, que é metade do aceite.
     *
     * Só aparece depois do blur e só com conteúdo escrito: o campo obrigatório
     * vazio já é assunto da regra `required` do FormKit, e acusar formato em campo
     * intocado é ruído. `error_message` do administrador vence o catálogo — quem
     * escreveu a regra sabe explicá-la melhor que uma mensagem genérica.
     */
    delegatedErrors(field) {
      if (!this.touchedFields.includes(field.name)) return [];
      const valor = this.formValues[field.name];
      if (String(valor ?? '').trim() === '') return [];
      const erro = fieldErrorFor(field, valor, { t: this.$t });
      return erro ? [erro.message] : [];
    },
    /**
     * Avança de etapa. Só passa quando a etapa atual não tem obrigatório vazio
     * nem erro de formato — validar no avanço é o que impede alguém chegar ao fim
     * e descobrir que o problema estava três telas atrás.
     */
    canLeaveCurrentStep() {
      return this.fieldsOfCurrentStep.every(field => {
        const valor = this.formValues[field.name];
        const vazio = String(valor ?? '').trim() === '';
        if (field.required && vazio) return false;
        if (vazio) return true;
        const erro = fieldErrorFor(field, valor, { t: this.$t });
        return !erro || erro.severity === 'warning';
      });
    },
    goToNextStep() {
      this.fieldsOfCurrentStep.forEach(field => this.markTouched(field.name));
      if (!this.canLeaveCurrentStep()) return;
      const proxima = this.visibleSteps.find(step => step > this.currentStep);
      if (proxima) this.currentStep = proxima;
    },
    onSubmit() {
      // O envio conclui o pré-chat: o rascunho pendente não pode chegar DEPOIS e
      // reabrir como incompleto um lead que já virou conversa.
      clearTimeout(this.partialLeadTimer);
      const { message } = this.formValues;
      // Bloco 3.15. Os quatro campos padrão saíam de `formValues` direto, sem
      // passar por `enabledPreChatFields` — então um campo que FICOU escondido
      // depois de preenchido (o gatilho mudou de resposta) ainda viajava com o
      // valor velho. Escondido é escondido para o envio também.
      const visivel = nome =>
        this.enabledPreChatFields.some(field => field.name === nome);
      const emailAddress = visivel('emailAddress')
        ? this.formValues.emailAddress
        : undefined;
      const fullName = visivel('fullName')
        ? this.formValues.fullName
        : undefined;
      const phoneNumber = visivel('phoneNumber')
        ? this.formValues.phoneNumber
        : undefined;
      this.$emit('submitPreChat', {
        fullName,
        phoneNumber,
        emailAddress,
        message,
        activeCampaignId: this.activeCampaign.id,
        conversationCustomAttributes: this.conversationCustomAttributes,
        contactCustomAttributes: this.contactCustomAttributes,
      });
    },
  },
};
</script>

<template>
  <!-- hide the default submit button for now -->
  <FormKit
    v-model="formValues"
    type="form"
    form-class="flex flex-col flex-1 w-full p-6 overflow-y-auto"
    :incomplete-message="false"
    :submit-attrs="{
      inputClass: 'hidden',
      wrapperClass: 'hidden',
    }"
    @submit="onSubmit"
  >
    <div
      v-if="shouldShowHeaderMessage"
      v-dompurify-html="formatMessage(headerMessage, false)"
      class="mb-4 text-base leading-5 text-n-slate-12 [&>p>.link]:text-w-brand-readable [&>p>.link]:hover:underline"
    />
    <!-- Why do the v-bind shenanigan? Because Formkit API is really bad.
    If we just pass the options as is even with null or undefined or false,
    it assumes we are trying to make a multicheckbox. This is the best we have for now -->
    <FormKit
      v-for="item in fieldsOfCurrentStep"
      :key="item.name"
      :name="item.name"
      :type="item.type"
      :label="getLabel(item)"
      :placeholder="getPlaceHolder(item)"
      :validation="getValidation(item)"
      v-bind="
        item.type === 'select'
          ? {
              options: getOptions(item),
            }
          : undefined
      "
      label-class="text-sm font-medium text-n-slate-12"
      :input-class="context => inputClass(context)"
      :validation-messages="{
        startsWithPlus: $t(
          'PRE_CHAT_FORM.FIELDS.PHONE_NUMBER.DIAL_CODE_VALID_ERROR'
        ),
        isValidPhoneNumber: $t('PRE_CHAT_FORM.FIELDS.PHONE_NUMBER.VALID_ERROR'),
        email: $t('PRE_CHAT_FORM.FIELDS.EMAIL_ADDRESS.VALID_ERROR'),
        required: getRequiredMessage(item),
        matches: item.regex_cue
          ? item.regex_cue
          : $t('PRE_CHAT_FORM.REGEX_ERROR'),
      }"
      :has-error-in-phone-input="hasErrorInPhoneInput"
      :errors="delegatedErrors(item)"
      :help="item.help_text || undefined"
      @blur="markTouched(item.name)"
    />
    <FormKit
      v-if="!hasActiveCampaign && isLastStep"
      name="message"
      type="textarea"
      label-class="text-sm font-medium text-n-slate-12"
      :input-class="context => inputClass(context)"
      :label="$t('PRE_CHAT_FORM.FIELDS.MESSAGE.LABEL')"
      :placeholder="$t('PRE_CHAT_FORM.FIELDS.MESSAGE.PLACEHOLDER')"
      validation="required"
      :validation-messages="{
        required: $t('PRE_CHAT_FORM.FIELDS.MESSAGE.ERROR'),
      }"
    />

    <!--
      Bloco 3.15 — com etapas, o botao avanca em vez de enviar ate a ultima.
      `type="button"` e o que impede o FormKit de submeter o formulario antes
      de o visitante ter visto os campos das etapas seguintes.
    -->
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

<style lang="scss">
.formkit-outer {
  @apply mt-2;

  .formkit-inner {
    input[type='checkbox'] {
      @apply size-4;

      // `outline-none` saiu daqui. O utilitário do Tailwind NÃO remove o anel:
      // ele gera `outline: 2px solid transparent`. Num checkbox — que é
      // focável e faz parte do caminho de teclado do pré-chat — isso deixava
      // 2px de anel INVISÍVEL, pior que nenhum: em `forced-colors` o
      // `transparent` é trocado por cor do sistema e o `none` não é.
      // O anel agora é o mesmo dos outros primitivos do widget, pelos tokens.
      &:focus-visible {
        outline: var(--w-focus-ring-width) solid var(--w-focus-ring-color);
        outline-offset: var(--w-focus-ring-offset);
      }
    }
  }

  &[data-invalid] {
    .formkit-label {
      @apply text-n-ruby-10;
    }
    .formkit-inner input,
    .formkit-inner textarea,
    .formkit-inner select {
      @apply outline-n-ruby-8 dark:outline-n-ruby-8 hover:outline-n-ruby-9 dark:hover:outline-n-ruby-9 focus:outline-n-ruby-9 dark:focus:outline-n-ruby-9;
    }
  }
}

[data-invalid] .formkit-message {
  @apply text-n-ruby-10 block text-xs font-normal my-0.5 w-full;
}

.formkit-outer[data-type='checkbox'] .formkit-wrapper {
  @apply flex items-center gap-2 px-0.5;
}

.formkit-messages {
  @apply list-none m-0 p-0;
}
</style>
