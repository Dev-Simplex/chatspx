<script>
/**
 * Bloco 4.03 — o passo de CAPTURA desenhado dentro da bolha da mensagem.
 *
 * Substitui o `shared/components/ChatForm.vue` **apenas** quando o passo declara
 * máscara, validador ou um campo de telefone — coisas que o ChatForm não conhece.
 * Formulário sem nada disso continua sendo desenhado pelo componente de sempre
 * (ver `message-types/FormContent.vue`): zero regressão para quem já usa `form`.
 *
 * DUAS REGRAS DE PRODUTO MORAM AQUI, e são as do bloco:
 *
 * 1. **Teto de 8 campos.** É o mesmo teto que o servidor recusa salvar
 *    (`Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS`) e que o `send_form` já
 *    corta. Aqui ele é a terceira linha de defesa: um passo antigo, gravado antes
 *    do teto, não desenha 12 campos numa bolha de 375 px.
 *
 * 2. **E-mail OU WhatsApp.** Campos de contato (`email` e `phone`) formam UM
 *    grupo: se algum deles é obrigatório, basta UM preenchido e válido para
 *    satisfazer o grupo inteiro. É o que "e-mail **ou** WhatsApp" quer dizer —
 *    pedir os dois e aceitar qualquer um. Sem essa regra, um passo que pede os
 *    dois obrigaria a pessoa a dar os dois, que é exatamente o atrito que o
 *    fluxo de captura existe para remover.
 */
import CaptureField from 'widget/capture/CaptureField.vue';

/** Teto de campos — espelha Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS. */
export const MAX_CAPTURE_FIELDS = 8;

/** Os tipos que contam como CANAL DE CONTATO para a regra "e-mail ou WhatsApp". */
const CONTACT_TYPES = ['email', 'phone'];

export const isContactField = field =>
  CONTACT_TYPES.includes(field?.type) ||
  ['email', 'corporate_email', 'phone'].includes(field?.validator);

export default {
  name: 'CaptureForm',
  components: { CaptureField },
  props: {
    items: { type: Array, default: () => [] },
    buttonLabel: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['submit'],
  data() {
    return { values: {}, validity: {} };
  },
  computed: {
    fields() {
      return this.items
        .filter(item => item && item.name)
        .slice(0, MAX_CAPTURE_FIELDS);
    },
    contactFields() {
      return this.fields.filter(isContactField);
    },
    /** O grupo só EXISTE quando há mais de um canal de contato e algum é obrigatório. */
    hasContactGroup() {
      return (
        this.contactFields.length > 1 &&
        this.contactFields.some(field => field.required)
      );
    },
    contactGroupSatisfied() {
      if (!this.hasContactGroup) return false;
      return this.contactFields.some(
        field =>
          String(this.values[field.name] ?? '').trim() !== '' &&
          this.validity[field.name] !== false
      );
    },
    isValid() {
      const everyFieldValid = this.fields.every(
        field => this.validity[field.name] !== false
      );
      if (!everyFieldValid) return false;
      return this.hasContactGroup ? this.contactGroupSatisfied : true;
    },
  },
  methods: {
    /**
     * Um campo do grupo de contato deixa de ser obrigatório em SI quando OUTRO
     * campo do grupo já foi preenchido — mas nunca ele mesmo, senão preencher um
     * campo o desobrigaria de estar correto.
     */
    isGroupSatisfiedFor(field) {
      if (!this.hasContactGroup || !isContactField(field)) return false;
      return this.contactFields.some(
        other =>
          other.name !== field.name &&
          String(this.values[other.name] ?? '').trim() !== '' &&
          this.validity[other.name] !== false
      );
    },
    onValidity({ name, valid }) {
      this.validity = { ...this.validity, [name]: valid };
    },
    onSubmit() {
      if (!this.isValid || this.disabled) return;
      this.$emit(
        'submit',
        this.fields.map(field => ({
          name: field.name,
          value: String(this.values[field.name] ?? '').trim(),
        }))
      );
    },
  },
};
</script>

<template>
  <!-- `w-full min-w-0` do contêiner até o input: é o que mantém o fluxo dentro de
       375 px sem barra horizontal. Nenhuma largura fixa, nenhuma unidade absoluta. -->
  <form
    class="flex flex-col w-full min-w-0 gap-3 p-4 chat-bubble agent bg-n-background dark:bg-n-solid-3"
    data-testid="capture-form"
    @submit.prevent="onSubmit"
  >
    <p v-if="hasContactGroup" class="text-xs break-words text-n-slate-11">
      {{ $t('CAPTURE.CONTACT_GROUP_HINT') }}
    </p>

    <CaptureField
      v-for="field in fields"
      :key="field.name"
      v-model="values[field.name]"
      :field="field"
      :disabled="disabled"
      :group-satisfied="isGroupSatisfiedFor(field)"
      @validity="onValidity"
    />

    <!-- `.button block` é o botão do widget (o mesmo do ChatForm) — não invento um
         segundo visual. `!whitespace-normal` desfaz o `whitespace-nowrap` do
         `.button`: um rótulo escrito pelo administrador ("Quero falar com um
         especialista agora") não cabe em 375 px numa linha só, e sem quebra ele
         estoura a bolha e traz a barra horizontal que o aceite proíbe. -->
    <button
      type="submit"
      class="button block !whitespace-normal !h-auto py-2 min-w-0"
      :disabled="!isValid || disabled"
      data-testid="capture-submit"
    >
      {{ buttonLabel || $t('CAPTURE.SUBMIT') }}
    </button>
  </form>
</template>
