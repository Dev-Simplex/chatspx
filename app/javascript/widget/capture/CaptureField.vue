<script>
/**
 * Bloco 4.03 — UM campo do fluxo de captura conversacional.
 *
 * O campo é desenhado DENTRO da bolha da mensagem (o passo chega como mensagem,
 * ver 4.02), e não numa tela de formulário à parte. Por isso ele é estreito por
 * natureza: o aceite do bloco é um fluxo de 4 campos concluir em **375 px sem
 * scroll horizontal**, que é a largura do menor telefone que ainda importa.
 *
 * MÁSCARA NO BLUR, e não a cada tecla, de propósito: numa caixa estreita, mascarar
 * enquanto se digita empurra o cursor a cada separador inserido — o visitante
 * digita 11 dígitos e vê o cursor pular três vezes. No blur o valor é normalizado
 * uma vez só, quando a pessoa já terminou. É o que o aceite pede, e a razão está aqui.
 *
 * As máscaras e os validadores vêm do bloco 3.13 (`shared/helpers/brMasks.js`) —
 * fonte única, o mesmo vocabulário que `Channel::WebWidget::PreChatFormSchema`
 * valida no servidor. Este componente não conhece regra brasileira nenhuma.
 */
import { applyMask, validateFieldValue } from 'widget/helpers/brMasks';

/** Tipo do backend → o `type` do <input>. `text_area` e `select` têm tag própria. */
const INPUT_TYPES = {
  email: 'email',
  phone: 'tel',
  text: 'text',
};

export default {
  name: 'CaptureField',
  props: {
    field: { type: Object, required: true },
    modelValue: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
    /**
     * O campo pertence a um grupo "e-mail OU WhatsApp" que JÁ foi satisfeito por
     * outro campo. Continua obrigatório no grupo, mas não em si — então não
     * mostramos "obrigatório" num campo que a pessoa não precisa preencher.
     */
    groupSatisfied: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'validity'],
  data() {
    return {
      touched: false,
      verdict: { valid: true, severity: null, code: null },
    };
  },
  computed: {
    fieldId() {
      return `capture-${this.field.name}`;
    },
    inputType() {
      return INPUT_TYPES[this.field.type] || 'text';
    },
    isTextArea() {
      return this.field.type === 'text_area';
    },
    isSelect() {
      return this.field.type === 'select';
    },
    isRequired() {
      return Boolean(this.field.required) && !this.groupSatisfied;
    },
    /**
     * A mensagem de erro é, em ordem: a que o cliente escreveu no construtor
     * (`error_message`, bloco 3.12), depois o texto do código devolvido pelo
     * validador. `code` é sufixo de chave, nunca texto pronto — ver brMasks.
     */
    message() {
      if (this.verdict.valid || !this.touched) return '';
      if (this.field.error_message) return this.field.error_message;
      // `code` vem do conjunto FECHADO de VALIDATORS de `brMasks.js` (bloco 3.13),
      // e a existência de TODAS as chaves em pt_BR e en é conferida por
      // `capture/specs/captureI18n.spec.js` — garantia mais forte que a do lint,
      // que só sabe olhar o literal. Por isso a regra é desligada nesta linha.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      return this.$t(`CAPTURE.VALIDATION.${this.verdict.code}`);
    },
    hasError() {
      return Boolean(this.message) && this.verdict.severity === 'error';
    },
    hasWarning() {
      return Boolean(this.message) && this.verdict.severity === 'warning';
    },
    describedBy() {
      if (this.message) return `${this.fieldId}-message`;
      return this.field.help_text ? `${this.fieldId}-help` : undefined;
    },
  },
  watch: {
    isRequired() {
      this.evaluate(this.modelValue);
    },
  },
  mounted() {
    this.evaluate(this.modelValue);
  },
  methods: {
    onInput(event) {
      this.$emit('update:modelValue', event.target.value);
      // Enquanto se digita, só o veredito muda (para liberar o botão); o texto
      // não é reescrito — ver a nota de máscara no cabeçalho.
      this.evaluate(event.target.value);
    },
    onBlur(event) {
      this.touched = true;
      const masked = this.field.mask
        ? applyMask(event.target.value, this.field.mask)
        : event.target.value;
      if (masked !== event.target.value)
        this.$emit('update:modelValue', masked);
      this.evaluate(masked);
    },
    evaluate(value) {
      this.verdict = validateFieldValue(value, {
        validator: this.field.validator,
        required: this.isRequired,
      });
      // `warning` é suave por decisão do 3.13: avisa e deixa enviar. Só `error`
      // trava, então é ele que o formulário consome.
      this.$emit('validity', {
        name: this.field.name,
        valid: this.verdict.valid || this.verdict.severity === 'warning',
      });
    },
  },
};
</script>

<template>
  <!-- `min-w-0` na coluna: sem ele, um <input> herda a largura intrínseca do
       navegador (~180 px) e o flex pai se recusa a encolher abaixo dela — é a
       causa clássica de barra horizontal em 375 px.

       Os campos NÃO recebem classe de estilo: `woot.scss` já estiliza
       `input:not(.reset-base)`, `textarea` e `select` com o visual do widget
       (largura total, foco na cor da marca, tema claro/escuro). Competir com ele
       por utilitária perde na especificidade e ainda criaria um segundo visual de
       campo dentro do mesmo widget. Só o estado de erro é acrescentado, e por um
       seletor mais específico que o global (ver o <style scoped>). -->
  <div class="flex flex-col w-full min-w-0 gap-1 capture-field">
    <label :for="fieldId" class="!text-xs !normal-case">
      {{ field.label }}
      <span v-if="!isRequired" class="font-normal text-n-slate-11">
        {{ $t('CAPTURE.OPTIONAL') }}
      </span>
    </label>

    <textarea
      v-if="isTextArea"
      :id="fieldId"
      :value="modelValue"
      :name="field.name"
      :placeholder="field.placeholder"
      :required="isRequired"
      :disabled="disabled"
      :aria-invalid="hasError"
      :aria-describedby="describedBy"
      rows="3"
      @input="onInput"
      @blur="onBlur"
    />

    <select
      v-else-if="isSelect"
      :id="fieldId"
      :value="modelValue"
      :name="field.name"
      :required="isRequired"
      :disabled="disabled"
      :aria-invalid="hasError"
      :aria-describedby="describedBy"
      @change="onInput"
      @blur="onBlur"
    >
      <option
        v-for="option in field.options || []"
        :key="option.key"
        :value="option.value"
      >
        {{ option.label }}
      </option>
    </select>

    <input
      v-else
      :id="fieldId"
      :value="modelValue"
      :type="inputType"
      :name="field.name"
      :placeholder="field.placeholder"
      :required="isRequired"
      :disabled="disabled"
      :aria-invalid="hasError"
      :aria-describedby="describedBy"
      @input="onInput"
      @blur="onBlur"
    />

    <p
      v-if="message"
      :id="`${fieldId}-message`"
      class="text-xs break-words"
      :class="hasError ? 'text-n-ruby-11' : 'text-n-amber-11'"
      role="alert"
    >
      {{ message }}
    </p>
    <p
      v-else-if="field.help_text"
      :id="`${fieldId}-help`"
      class="text-xs break-words text-n-slate-11"
    >
      {{ field.help_text }}
    </p>
  </div>
</template>

<style scoped lang="scss">
/**
 * O global de `woot.scss` é `input:not(.reset-base)` — especificidade (0,1,1).
 * Uma utilitária de classe (0,1,0) perderia dele em qualquer ordem de arquivo, e
 * a borda de erro simplesmente não apareceria: defeito silencioso, sem erro de
 * build. Este seletor tem (0,2,1) e vence sem precisar de `!important`.
 */
.capture-field input[aria-invalid='true'],
.capture-field textarea[aria-invalid='true'],
.capture-field select[aria-invalid='true'] {
  @apply outline-n-ruby-8 hover:outline-n-ruby-9;
}
</style>
