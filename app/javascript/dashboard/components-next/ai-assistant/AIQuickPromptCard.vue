<script setup>
import { computed, getCurrentInstance } from 'vue';

/**
 * Cartão de sugestão do estado vazio, na linguagem da OpenAI
 * (public/mockups/copiloto-v2.html, seletor `.qp button`): retângulo de canto
 * 12px, borda `--oa-line`, fundo do painel, texto à esquerda e uma segunda
 * linha menor explicando o que a ação faz. Hover só escurece o fundo
 * (`--oa-hover`) — nenhum realce colorido, nenhum "lift".
 *
 * ⚠️ `border-solid` NÃO é decoração: `_base.scss` aplica `border-0
 * border-none` a TODO `<button>` do produto. A classe `.border` do Tailwind
 * só define a LARGURA, então sem restabelecer o `border-style` o cartão
 * computava `border-style: none` e ficava 1,00:1 contra o fundo — invisível.
 * Medido e corrigido em 2026-07-29; vale para qualquer `<button>` daqui.
 *
 * É aqui que nos afastamos do ChatGPT de propósito: ele abre em branco, e o
 * agente que está com um cliente esperando não veio explorar, veio resolver.
 *
 * Estado desabilitado mostra `cursor-not-allowed` e expõe o motivo por
 * `aria-describedby` (ex.: "Modo nota privada").
 *
 * ⚠️ O desabilitado NÃO usa `opacity`. Ele usava `opacity-40`, e a opacidade
 * do pai multiplica tudo — inclusive a linha que explica POR QUE o cartão
 * está fora do ar, que é a única informação que importa nesse estado. Ficava
 * ilegível (medido: 1,85:1). Agora o estado é dito com os tokens: moldura
 * `--oa-line-soft`, fundo `--oa-side` e texto `--oa-ink-2`, em opacidade
 * cheia (6,25:1 claro / 8,65:1 escuro).
 *
 * `disabled:opacity-100` é o que torna isso possível: `_base.scss:286` aplica
 * `disabled:opacity-50` a TODO `<button>` do produto, então tirar a nossa
 * classe não bastava — a global continuava lavando o cartão. É o mesmo
 * problema do `border-none` logo abaixo, no mesmo `@apply`.
 */

const props = defineProps({
  icon: { type: String, default: '' },
  label: { type: String, required: true },
  description: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  disabledReason: { type: String, default: '' },
});

const emit = defineEmits(['click']);

// Local stable id per instance — avoids relying on Vue 3.5 `useId` which is
// not exported by all bundler builds in our pinned version.
const instanceUid =
  getCurrentInstance()?.uid ?? Math.floor(Math.random() * 1e9);
const descriptionId = `aiqp-${instanceUid}-desc`;
const reasonId = `aiqp-${instanceUid}-reason`;

const ariaDescribedBy = computed(() => {
  if (props.disabled && props.disabledReason) return reasonId;
  if (props.description) return descriptionId;
  return undefined;
});

function handleClick() {
  if (props.disabled) return;
  emit('click');
}
</script>

<template>
  <button
    type="button"
    data-testid="ai-quick-prompt-card"
    :aria-label="label"
    :aria-describedby="ariaDescribedBy"
    :aria-disabled="disabled ? 'true' : 'false'"
    :disabled="disabled"
    :title="disabled && disabledReason ? disabledReason : undefined"
    class="flex w-full items-start gap-2.5 rounded-xl border border-solid px-[13px] py-[11px] text-left text-[13.5px] leading-[1.4] transition-colors min-h-[44px] disabled:opacity-100 focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[var(--oa-focus)] forced-colors:border-2 forced-colors:border-current"
    :class="
      disabled
        ? 'cursor-not-allowed border-[var(--oa-line-soft)] bg-[var(--oa-side)] text-[var(--oa-ink-2)]'
        : 'border-[var(--oa-line)] bg-[var(--oa-bg)] text-[var(--oa-ink)] hover:bg-[var(--oa-hover)]'
    "
    @click="handleClick"
  >
    <span
      v-if="icon"
      aria-hidden="true"
      class="mt-0.5 inline-flex size-4 shrink-0 items-center justify-center text-[var(--oa-ink-2)]"
      :class="icon"
    />
    <span class="flex min-w-0 flex-1 flex-col">
      <!-- peso, não cor: é o `font-medium` que separa a ação da explicação -->
      <span class="font-medium">{{ label }}</span>
      <span
        v-if="description"
        :id="descriptionId"
        class="mt-[3px] block text-xs leading-[1.35] text-[var(--oa-ink-2)]"
      >
        {{ description }}
      </span>
      <!-- É a razão de o cartão estar fora do ar: legível como a descrição. -->
      <span
        v-if="disabled && disabledReason"
        :id="reasonId"
        class="mt-[3px] block text-xs leading-[1.35] text-[var(--oa-ink-2)]"
      >
        {{ disabledReason }}
      </span>
    </span>
  </button>
</template>
