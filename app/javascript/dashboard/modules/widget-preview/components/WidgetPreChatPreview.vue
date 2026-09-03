<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLabel, getPlaceHolder } from 'dashboard/helper/preChat';
import {
  fieldsOfStep,
  stepCount,
} from 'dashboard/routes/dashboard/settings/inbox/widget/prechat/preChatModel';

/**
 * Bloco 3.16 — a etapa 1 do pré-chat dentro do preview.
 *
 * O aceite é *"o que a tela configura é o que o preview mostra"*, e ele só se
 * sustenta se os dois lados usarem **a mesma função** para decidir quais campos
 * entram e em que ordem. Por isso `fieldsOfStep` vem do `preChatModel` do
 * construtor, e não de uma cópia daqui: uma segunda regra de ordenação
 * divergiria da primeira sem ninguém notar — que é exatamente a dívida **D4**
 * que o 3.10 acabou de pagar com a paleta.
 *
 * Os rótulos passam por `getLabel`/`getPlaceHolder`, o mesmo caminho da tela e
 * do widget: campo padrão sem rótulo gravado cai no texto traduzido, e não no
 * nome interno (`emailAddress`) que o visitante não deveria ler.
 *
 * A cor vem por token (`bg-w-brand` / `text-w-on-brand`), nunca por prop de
 * cor: reintroduzir a prop recriaria a segunda fonte de verdade que o 3.10
 * eliminou.
 *
 * E NENHUM texto daqui usa classe `n-*`. Não é preferência de estilo: medido no
 * Chromium, `_wa-skin.scss` tem, sob `.dark`, regras como
 * `[class*='text-n-slate-12'] { color: #e9edef !important }`. Com o painel
 * escuro e o preview claro — a combinação que o 3.10 tornou possível —, o
 * rótulo saía `rgb(233,237,239)` em vez de `rgb(28,32,36)`: quase branco, sobre
 * um painel que o preview quer branco. `!important` vence a custom property,
 * então herdar o token certo não basta; é preciso não casar com o seletor. As
 * classes abaixo consomem as mesmas variáveis, sem o nome que o skin persegue.
 * Mecanismo: `specs/browser/prechat-preview-colors.check.mjs`.
 */
const props = defineProps({
  options: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

const fields = computed(() =>
  fieldsOfStep(props.options?.pre_chat_fields ?? [], 1)
);

const totalSteps = computed(() =>
  stepCount(props.options?.pre_chat_fields ?? [])
);

const message = computed(() => props.options?.pre_chat_message ?? '');

const labelOf = field => getLabel({ key: field.name, label: field.label }, t);

const placeholderOf = field =>
  getPlaceHolder({ key: field.name, placeholder: field.placeholder }, t);
</script>

<template>
  <div class="px-4 py-3 flex flex-col gap-3" data-testid="prechat-preview">
    <p v-if="message" class="m-0 text-sm wp-pc-strong">{{ message }}</p>

    <p
      v-if="!fields.length"
      class="m-0 text-sm wp-pc-muted"
      data-testid="prechat-preview-empty"
    >
      {{ t('INBOX_WIDGET.PRE_CHAT_FORM.PREVIEW.EMPTY') }}
    </p>

    <div
      v-for="field in fields"
      :key="field.name"
      class="flex flex-col gap-1"
      data-testid="prechat-preview-field"
    >
      <span
        class="text-xs font-medium wp-pc-strong"
        data-testid="prechat-preview-label"
      >
        {{ labelOf(field) }}
        <span
          v-if="field.required"
          class="wp-pc-required"
          data-testid="prechat-preview-required"
          >*</span
        >
      </span>
      <div
        class="px-3 py-2 text-sm rounded-lg outline outline-1 -outline-offset-1 wp-pc-box wp-pc-faint"
        data-testid="prechat-preview-placeholder"
      >
        {{ placeholderOf(field) }}
      </div>
      <span
        v-if="field.help_text"
        class="text-xxs wp-pc-muted"
        data-testid="prechat-preview-help"
      >
        {{ field.help_text }}
      </span>
    </div>

    <button
      class="px-4 py-2 text-sm font-medium rounded-lg bg-w-brand text-w-on-brand"
      data-testid="prechat-preview-submit"
    >
      {{ t('INBOX_WIDGET.PRE_CHAT_FORM.PREVIEW.START') }}
    </button>

    <span
      v-if="totalSteps > 1"
      class="text-xxs wp-pc-muted"
      data-testid="prechat-preview-steps"
    >
      {{
        t('INBOX_WIDGET.PRE_CHAT_FORM.PREVIEW.STEP_OF', {
          step: 1,
          total: totalSteps,
        })
      }}
    </span>
  </div>
</template>

<style scoped>
/* As mesmas variáveis que as classes `n-*` consumiriam — o preview as declara
   no wrapper (`.wp-theme-light` / `.wp-theme-dark`, bloco 3.10) a partir dos
   mixins do widget. O que muda é só o NOME da classe, que deixa de casar com
   os seletores `[class*='text-n-slate-*']` do skin do dashboard. */
.wp-pc-strong {
  color: rgb(var(--slate-12));
}

.wp-pc-muted {
  color: rgb(var(--slate-11));
}

.wp-pc-faint {
  color: rgb(var(--slate-10));
}

.wp-pc-required {
  color: rgb(var(--ruby-11));
}

.wp-pc-box {
  outline-color: rgb(var(--slate-6));
}
</style>
