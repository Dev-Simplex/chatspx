<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import AutoOpenWarningDialog from './AutoOpenWarningDialog.vue';
import {
  APPROACHES,
  DEFAULT_APPROACH,
  resolveMobileApproach,
} from '../composables/widgetTriggersContract';

/**
 * O seletor dos tres niveis de abordagem (bloco 3.20 / decisao D1), com o que
 * cada um FAZ escrito ao lado — nao o nome sozinho.
 *
 * Duas regras que a tela nao pode deixar implicitas:
 *
 *  1. **Celular nunca recebe `aggressive`.** Quem recusa e o schema (422), mas
 *     a tela precisa DIZER, antes de salvar, qual nivel o celular vai usar —
 *     senao o administrador escolhe "Agressivo" e acha que ligou no telefone.
 *  2. **A degradacao por familiaridade nasce ligada**, e a tela explica em uma
 *     frase o que ela faz com quem volta. Nao e enfeite: e o que impede a
 *     abordagem de virar perseguicao.
 */
const props = defineProps({
  approach: { type: String, default: DEFAULT_APPROACH },
  approachMobile: { type: String, default: '' },
  degradeOnReturn: { type: Boolean, default: true },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const isDialogOpen = ref(false);

/** O nivel que o celular usa de verdade — mesma conta do servidor. */
const mobileLevel = computed(() =>
  resolveMobileApproach(props.approachMobile, props.approach)
);

/* As strings da abordagem ja existiam no namespace APPROACH — a trilha do
   backend as declarou junto do schema de 3.20, sem consumidor. Esta tela e o
   consumidor. Criar um segundo namespace daria duas verdades para o mesmo
   nivel, e uma delas envelheceria calada. */
const label = level =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.APPROACH.LEVELS.${level.toUpperCase()}.LABEL`);

const description = level =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.APPROACH.LEVELS.${level.toUpperCase()}.DESCRIPTION`);

const select = level => {
  if (level === props.approach) return;

  if (level === 'aggressive') {
    // Nada e gravado antes do administrador ler o que vai acontecer.
    isDialogOpen.value = true;
    return;
  }
  emit('update', { approach: level, approach_mobile: level });
};

const confirmAggressive = () => {
  isDialogOpen.value = false;
  // O celular fica em `bold` EXPLICITAMENTE. O servidor tambem resolveria
  // assim, mas gravar o valor deixa o dado dizendo o que acontece, em vez de
  // depender de uma resolucao que so existe do outro lado.
  emit('update', { approach: 'aggressive', approach_mobile: DEFAULT_APPROACH });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="grid gap-3 lg:grid-cols-3">
      <RadioCard
        v-for="level in APPROACHES"
        :id="`approach-${level}`"
        :key="level"
        :label="label(level)"
        :description="description(level)"
        :is-active="approach === level"
        :data-testid="`approach-${level}`"
        @select="select(level)"
      />
    </div>

    <p class="text-sm text-n-slate-11" data-testid="approach-mobile-note">
      {{
        t('INBOX_WIDGET.APPROACH.MOBILE.APPLIED_LEVEL', {
          level: label(mobileLevel),
        })
      }}
    </p>

    <div class="flex flex-col gap-2">
      <div class="flex items-center gap-3">
        <Switch
          :model-value="degradeOnReturn"
          :aria-label="t('INBOX_WIDGET.APPROACH.DEGRADE_ON_RETURN.LABEL')"
          data-testid="degrade-switch"
          @update:model-value="emit('update', { degrade_on_return: $event })"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.APPROACH.DEGRADE_ON_RETURN.LABEL') }}
        </span>
      </div>
      <p class="text-sm text-n-slate-11" data-testid="degrade-sentence">
        {{ t('INBOX_WIDGET.APPROACH.DEGRADE_ON_RETURN.SENTENCE') }}
      </p>
      <Banner
        v-if="!degradeOnReturn"
        color="amber"
        data-testid="degrade-off-warning"
      >
        {{ t('INBOX_WIDGET.APPROACH.DEGRADE_ON_RETURN.OFF_WARNING') }}
      </Banner>
    </div>

    <AutoOpenWarningDialog
      :open="isDialogOpen"
      :mobile-level="mobileLevel"
      @confirm="confirmAggressive"
      @cancel="isDialogOpen = false"
    />
  </div>
</template>
