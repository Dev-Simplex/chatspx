<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * O escape da regra 1 do perfil: **ele esconde, não remove.**
 *
 * Toda seção que o perfil ativo oculta continua alcançável por aqui, sem trocar
 * o perfil e sem sujar o rascunho. Um cliente de suporte que queira medir
 * conversão não pode ficar refém do rótulo que escolheu na criação da caixa —
 * e um administrador que não encontra a configuração assume que ela não existe.
 *
 * O texto diz as duas coisas de propósito: *quem* esconde (o perfil ativo) e
 * que o escondido **continua gravado**.
 */
const props = defineProps({
  /** O perfil ativo — o que está escondendo a seção. */
  activeProfile: { type: String, required: true },
  /** O outro perfil — o dono das seções escondidas. */
  otherProfile: { type: String, required: true },
  /** Se as seções do outro perfil já estão à vista. */
  showing: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const { t } = useI18n();

const label = profile =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.PROFILE.${profile.toUpperCase()}.LABEL`);

const hint = computed(() =>
  t('INBOX_WIDGET.PROFILE.HIDDEN_HINT', { profile: label(props.activeProfile) })
);

const action = computed(() =>
  props.showing
    ? t('INBOX_WIDGET.PROFILE.HIDE_OTHER', {
        profile: label(props.otherProfile),
      })
    : t('INBOX_WIDGET.PROFILE.SHOW_OTHER', {
        profile: label(props.otherProfile),
      })
);
</script>

<template>
  <div
    class="flex flex-col items-start gap-1 py-3"
    data-testid="profile-escape"
  >
    <p class="text-sm text-n-slate-11">{{ hint }}</p>
    <button
      type="button"
      class="text-sm font-medium underline text-n-brand hover:no-underline"
      data-testid="profile-escape-toggle"
      :aria-expanded="showing"
      @click="emit('toggle')"
    >
      {{ action }}
    </button>
  </div>
</template>
