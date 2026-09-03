<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  contrastPairs,
  formatRatio,
  isValidHex,
} from '../composables/useContrast';

/**
 * O medidor de contraste — o coracao da tela de aparencia.
 *
 * Ele INFORMA, nunca impede o salvamento: a liberdade fica na marca, a garantia
 * fica no token. Para cada um dos quatro pares mostra a razao da cor crua, se
 * ela passa, e — quando nao passa — a cor que o widget vai usar no lugar, com a
 * razao dela. Sem isso, o cliente escolhe a cor e nao tem como saber que o
 * proprio header ficou ilegivel.
 *
 * Nunca usa `opacity` para simular estado: opacidade muda a luminancia e
 * invalidaria a conta que esta tela esta exibindo (regra C10).
 */
const props = defineProps({
  color: { type: String, default: '' },
});

const { t, locale } = useI18n();

const pairs = computed(() => contrastPairs(props.color));
const isValid = computed(() => isValidHex(props.color));

const localeTag = computed(() => (locale.value === 'en' ? 'en-US' : 'pt-BR'));
const ratio = value =>
  t('INBOX_WIDGET.CONTRAST.RATIO', {
    value: formatRatio(value, localeTag.value),
  });

/* A seta vem do i18n, e nao crua no template: em arabe e hebraico a direcao da
   leitura inverte e uma seta literal aponta para o lado errado. */
const adjustedRatio = value =>
  t('INBOX_WIDGET.CONTRAST.ADJUSTED_TO', {
    value: formatRatio(value, localeTag.value),
  });

const verdict = pair => {
  if (pair.adjustedColor) return 'adjusted';
  return pair.passes ? 'pass' : 'fail';
};

const verdictLabel = pair =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.CONTRAST.VERDICT.${verdict(pair).toUpperCase()}`);

/** A frase que explica o ajuste, com os dois numeros e as duas cores. */
const explanation = computed(() => {
  const adjusted = pairs.value.find(pair => pair.adjustedColor);
  if (!adjusted) return '';
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(
    `INBOX_WIDGET.CONTRAST.EXPLANATION.${adjusted.id === 'brandAsBorder' ? 'BORDER' : 'TEXT'}`,
    {
      brand: props.color.toUpperCase(),
      ratio: formatRatio(adjusted.ratio, localeTag.value),
      adjusted: adjusted.adjustedColor.toUpperCase(),
      adjustedRatio: formatRatio(adjusted.adjustedRatio, localeTag.value),
    }
  );
});
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="contrast-readout">
    <p v-if="!isValid" class="text-sm text-n-slate-11">
      {{ t('INBOX_WIDGET.CONTRAST.INVALID') }}
    </p>

    <template v-else>
      <ul class="flex flex-col gap-2">
        <li
          v-for="pair in pairs"
          :key="pair.id"
          class="flex items-center justify-between gap-3 text-sm"
          :data-testid="`contrast-${pair.id}`"
        >
          <span class="text-n-slate-11">
            <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
            {{ t(`INBOX_WIDGET.CONTRAST.PAIRS.${pair.id.toUpperCase()}`) }}
          </span>
          <span class="flex items-center gap-2 shrink-0">
            <span
              class="w-4 h-4 border rounded border-n-weak"
              :style="{ backgroundColor: pair.adjustedColor || pair.color }"
            />
            <span class="tabular-nums text-n-slate-12" data-testid="ratio">
              {{ ratio(pair.ratio) }}
            </span>
            <span
              v-if="pair.adjustedColor"
              class="tabular-nums text-n-slate-11"
              data-testid="adjusted-ratio"
            >
              {{ adjustedRatio(pair.adjustedRatio) }}
            </span>
            <span
              class="text-xs"
              :class="{
                'text-n-teal-11': verdict(pair) === 'pass',
                'text-n-amber-11': verdict(pair) === 'adjusted',
                'text-n-ruby-11': verdict(pair) === 'fail',
              }"
              :data-testid="`verdict-${verdict(pair)}`"
            >
              {{ verdictLabel(pair) }}
            </span>
          </span>
        </li>
      </ul>

      <p
        v-if="explanation"
        class="text-sm text-n-slate-11"
        data-testid="contrast-explanation"
      >
        {{ explanation }}
      </p>
    </template>
  </div>
</template>
