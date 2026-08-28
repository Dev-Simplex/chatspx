<script>
import { FormKit, createInput } from '@formkit/vue';
import { getRegexp } from 'shared/helpers/Validators';
import PhoneInput from 'widget/components/Form/PhoneInput.vue';
import { getRequiredMessage } from 'widget/helpers/preChatFieldMessages';
import { rotuloObrigatorio } from './rotulos';

/**
 * UM CAMPO DO PRÉ-CHAT — o destino da delegação do bloco 3.15.
 *
 * Este é o "→ widget/ui/WField.vue" da linha do bloco no §2.2: a marcação de um
 * campo, com o tipo, as opções, as regras e as mensagens, sai de
 * `PreChat/Form.vue` (campo minado, R15) e passa a morar aqui, num arquivo que o
 * upstream não toca. A casca lá ficou com menos de 60 linhas por causa disto.
 *
 * O CONTROLE é do FormKit, e não um `<input>` nosso: o pré-chat depende do motor
 * de validação dele (`email`, `matches`, `required`, o input de telefone criado
 * por `createInput`), e trocá-lo seria reescrever o formulário — exatamente o
 * que o bloco proíbe. A associação rótulo↔campo, que é o contrato de
 * acessibilidade deste componente, é a que o FormKit gera: um `<label for>`
 * apontando para o `id` do controle.
 *
 * `label` continua sendo prop obrigatória e validada (`rotuloObrigatorio`):
 * campo sem nome acessível é a violação que a matriz de snapshot mediu, e ela
 * não volta por uma refatoração.
 */

// Fora do componente de propósito: a definição do input é a MESMA para todas as
// instâncias, e criá-la por campo montado seria uma definição nova por render.
const phoneInput = createInput(PhoneInput, {
  props: ['hasErrorInPhoneInput'],
});

/** Tipo do painel → tipo do FormKit. `phoneNumber` tem input próprio. */
const TYPE_ALIASES = { link: 'url', list: 'select' };

export default {
  name: 'WField',
  components: { FormKit },
  props: {
    field: { type: Object, required: true },
    label: { type: String, required: true, validator: rotuloObrigatorio },
    errors: { type: Array, default: () => [] },
  },
  emits: ['blur'],
  data() {
    return { hasErrorInPhoneInput: false };
  },
  computed: {
    resolvedType() {
      if (this.field.name === 'phoneNumber') return phoneInput;
      return TYPE_ALIASES[this.field.type] || this.field.type;
    },
    isSelect() {
      return this.resolvedType === 'select';
    },
    /**
     * As opções indexadas por POSIÇÃO. É desta indexação que nasce o defeito que
     * o 3.15 fecha: o FormKit guarda `'0'`, e quem configura a condicional no
     * painel digita "Empresa". Quem resolve é `preChatFieldRules`; aqui só se
     * declara a forma.
     */
    options() {
      if (!this.isSelect) return undefined;
      return Object.fromEntries(
        (this.field.values || []).map((value, index) => [index, value])
      );
    },
    validation() {
      const {
        name,
        type,
        field_type: fieldType,
        regex_pattern: pattern,
      } = this.field;
      const regex = pattern ? getRegexp(pattern) : null;
      // O FormKit guarda a RegExp e chama `.test()` a cada tecla; as flags `g` e
      // `y` mantêm `lastIndex` e fariam a validade oscilar entre teclas.
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
      const keys = Object.keys(validations);
      const baseRules = this.field.required ? [['required']] : [['optional']];

      if (
        !keys.includes(name) &&
        !keys.includes(type) &&
        !keys.includes(fieldType)
      ) {
        return '';
      }

      const validationType =
        validations[type] || validations[name] || validations[fieldType];
      if (!validationType) return baseRules;

      // Normalizado em array-de-arrays para que a RegExp de `['matches', regex]`
      // sobreviva sem ser convertida em string pelo FormKit.
      const extraRules = Array.isArray(validationType)
        ? validationType.map(rule => (Array.isArray(rule) ? rule : [rule]))
        : [[validationType]];

      return baseRules.concat(extraRules);
    },
    validationMessages() {
      return {
        startsWithPlus: this.$t(
          'PRE_CHAT_FORM.FIELDS.PHONE_NUMBER.DIAL_CODE_VALID_ERROR'
        ),
        isValidPhoneNumber: this.$t(
          'PRE_CHAT_FORM.FIELDS.PHONE_NUMBER.VALID_ERROR'
        ),
        email: this.$t('PRE_CHAT_FORM.FIELDS.EMAIL_ADDRESS.VALID_ERROR'),
        // Bloco 2.17: a mensagem de obrigatoriedade NOMEIA o campo em vez de
        // repetir a mesma palavra em todos eles.
        required: getRequiredMessage({ field: this.field, t: this.$t }),
        matches: this.field.regex_cue || this.$t('PRE_CHAT_FORM.REGEX_ERROR'),
      };
    },
  },
  methods: {
    inputClass(input) {
      const { state, family: classification, type } = input.context;
      if (classification === 'box' && type === 'checkbox') return '';
      if (type === 'phoneInput') this.hasErrorInPhoneInput = state.invalid;
      return 'mt-1 rounded w-full py-2 px-3';
    },
  },
};
</script>

<template>
  <!-- O `v-bind` condicional das opções é exigência do FormKit: receber a chave
       `options` com `undefined` já o faz assumir multi-checkbox. -->
  <FormKit
    :name="field.name"
    :type="resolvedType"
    :label="label"
    :placeholder="field.placeholder"
    :validation="validation"
    :validation-messages="validationMessages"
    v-bind="isSelect ? { options } : undefined"
    label-class="text-sm font-medium text-n-slate-12"
    :input-class="context => inputClass(context)"
    :has-error-in-phone-input="hasErrorInPhoneInput"
    :errors="errors"
    :help="field.help_text || undefined"
    @blur="$emit('blur', field.name)"
  />
</template>

<style lang="scss">
/**
 * GLOBAL de propósito, e não `scoped`: o FormKit renderiza a árvore do campo
 * fora do escopo do componente que o declara, então `scoped` não alcançaria
 * `.formkit-outer`. Estas regras vieram inteiras de `PreChat/Form.vue`.
 */
.formkit-outer {
  @apply mt-2;

  .formkit-inner {
    input[type='checkbox'] {
      @apply size-4;

      // `outline-none` não entra aqui. O utilitário do Tailwind NÃO remove o
      // anel: ele gera `outline: 2px solid transparent`. Num checkbox — que é
      // focável e faz parte do caminho de teclado do pré-chat — isso deixava
      // 2px de anel INVISÍVEL, pior que nenhum: em `forced-colors` o
      // `transparent` é trocado por cor do sistema e o `none` não é.
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
