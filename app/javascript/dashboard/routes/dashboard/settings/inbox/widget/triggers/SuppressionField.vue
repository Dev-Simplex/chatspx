<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import {
  DEFAULT_MIN_VIEWPORT_WIDTH,
  TRIGGER_LIMITS,
} from '../composables/widgetTriggersContract';

/**
 * "Quando nao aparecer" — T3.5.
 *
 * A secao irma de "onde aparecer", e a diferenca entre as duas nao e cosmetica:
 * `audience` responde ONDE o convite PODE aparecer, esta aqui responde quando
 * ele SE CALA mesmo estando no lugar certo. Sao as tres unicas situacoes que o
 * plano nomeia, e as tres sao decidiveis pelo NAVEGADOR — o que mantem a
 * arbitragem A5 de pe, sem endpoint novo:
 *
 *  · banner de cookies visivel — o convite competiria com a caixa que o
 *    visitante e obrigado a responder primeiro;
 *  · tela estreita — abaixo do breakpoint unico (768) o painel e tela cheia, e
 *    convite proativo sobre tela cheia e a reclamacao que o estudo documenta;
 *  · fora do horario comercial — `working_hours`, `working_hours_enabled`,
 *    `timezone` e `utc_off_set` JA viajam no payload de boot
 *    (`configs/create.json.jbuilder:24,40,46-47`), entao o SDK responde essa
 *    pergunta sozinho.
 *
 * Nao ha nada aqui ligado por padrao: um convite que se cala sozinho sem
 * ninguem pedir e tao surpreendente quanto um que aparece sem ninguem pedir.
 */
const props = defineProps({
  suppress: { type: Object, default: () => ({}) },
  /**
   * `working_hours_enabled` da inbox. Falso nao ESCONDE a opcao — esconder
   * faria a regra sumir da tela sem explicacao. Ele mostra, ao lado, que marcar
   * esta caixa nao vai calar convite nenhum enquanto a caixa de entrada nao
   * tiver horario configurado.
   */
  businessHoursConfigured: { type: Boolean, default: false },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const set = patch => emit('update', { ...props.suppress, ...patch });

const cookieBanner = computed(() => Boolean(props.suppress.cookie_banner));
const outsideBusinessHours = computed(() =>
  Boolean(props.suppress.outside_business_hours)
);

/**
 * Zero e "sem corte", e nao "corte em zero": e por isso que a caixa marcada
 * grava o breakpoint e a desmarcada apaga a chave, em vez de gravar 0 — chave
 * ausente e a ausencia de regra, que e o que o A4 pede das quatro chaves.
 */
const narrowScreen = computed(
  () => Number(props.suppress.min_viewport_width) > 0
);
const minWidth = computed(
  () => props.suppress.min_viewport_width ?? DEFAULT_MIN_VIEWPORT_WIDTH
);

const toggleNarrowScreen = () => {
  if (narrowScreen.value) {
    const proximo = { ...props.suppress };
    delete proximo.min_viewport_width;
    emit('update', proximo);
    return;
  }
  set({ min_viewport_width: DEFAULT_MIN_VIEWPORT_WIDTH });
};

const setMinWidth = valor =>
  set({
    min_viewport_width: Math.min(
      TRIGGER_LIMITS.viewportWidthMax,
      Math.max(TRIGGER_LIMITS.viewportWidthMin, Number(valor) || 0)
    ),
  });
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="suppress-field">
    <p class="text-sm text-n-slate-11">
      {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.HINT') }}
    </p>

    <div class="flex items-start gap-2">
      <input
        id="suppress-cookie-banner"
        type="checkbox"
        class="mt-1"
        :checked="cookieBanner"
        data-testid="suppress-cookie-banner"
        @change="set({ cookie_banner: !cookieBanner })"
      />
      <label for="suppress-cookie-banner" class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.COOKIE_BANNER') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.COOKIE_BANNER_HINT') }}
        </span>
      </label>
    </div>

    <div class="flex flex-col gap-2">
      <div class="flex items-start gap-2">
        <input
          id="suppress-narrow-screen"
          type="checkbox"
          class="mt-1"
          :checked="narrowScreen"
          data-testid="suppress-narrow-screen"
          @change="toggleNarrowScreen"
        />
        <label for="suppress-narrow-screen" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.NARROW_SCREEN') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.NARROW_SCREEN_HINT') }}
          </span>
        </label>
      </div>
      <div
        v-if="narrowScreen"
        class="flex items-center gap-2 ltr:ml-6 rtl:mr-6"
      >
        <Input
          type="number"
          class="w-24"
          :model-value="minWidth"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.SUPPRESS.MIN_WIDTH')"
          data-testid="suppress-min-width"
          @update:model-value="setMinWidth($event)"
        />
        <span class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.MIN_WIDTH_UNIT') }}
        </span>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <div class="flex items-start gap-2">
        <input
          id="suppress-business-hours"
          type="checkbox"
          class="mt-1"
          :checked="outsideBusinessHours"
          data-testid="suppress-business-hours"
          @change="set({ outside_business_hours: !outsideBusinessHours })"
        />
        <label for="suppress-business-hours" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.BUSINESS_HOURS') }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.BUSINESS_HOURS_HINT') }}
          </span>
        </label>
      </div>
      <!-- `text-n-amber-12` pelo mesmo motivo medido no aviso do gatilho
           composto: o tom 11 da escala reprova AA no tema claro. -->
      <Banner
        v-if="outsideBusinessHours && !businessHoursConfigured"
        color="amber"
        data-testid="business-hours-missing"
      >
        <span class="text-n-amber-12">
          {{ t('INBOX_WIDGET.TRIGGERS.SUPPRESS.BUSINESS_HOURS_MISSING') }}
        </span>
      </Banner>
    </div>
  </div>
</template>
