<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  pendingProposals,
  keptValues,
} from './composables/useProfileVisibility';

/**
 * O diálogo da troca de perfil.
 *
 * Ele existe porque a troca **propõe** e nunca reescreve (A3, regime 2). Lista
 * nominalmente, com caixa marcável, cada valor que mudaria — e lista também, em
 * texto, o que **continua gravado**. Nada é apagado: a configuração do perfil
 * anterior fica no banco, inerte, e volta se o perfil voltar.
 */
const props = defineProps({
  open: { type: Boolean, default: false },
  targetProfile: { type: String, default: 'support' },
  currentValues: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
const dialogRef = ref(null);
const accepted = ref([]);

const proposals = computed(() =>
  pendingProposals(props.targetProfile, props.currentValues)
);
const kept = computed(() =>
  keptValues(props.targetProfile, props.currentValues)
);

// Nascem marcadas: quem escolheu o perfil quer o perfil. O que a caixa oferece
// é o direito de recusar item a item, não a obrigação de reconstruir tudo.
watch(
  () => [props.open, props.targetProfile],
  ([isOpen]) => {
    if (isOpen) {
      accepted.value = proposals.value.map(proposal => proposal.id);
      dialogRef.value?.open();
    } else {
      dialogRef.value?.close();
    }
  }
);

const toggle = id => {
  accepted.value = accepted.value.includes(id)
    ? accepted.value.filter(item => item !== id)
    : [...accepted.value, id];
};

/**
 * A proposta DERIVADA (bloco 3.07) é listada sem caixa.
 *
 * Ela não tem campo gravado: quem a resolve é o perfil, no servidor
 * (`WidgetProfile::PROFILE_DEFAULTS`). O aceite manda listar nominalmente tudo
 * que muda — então ela aparece —, mas uma caixa que não muda nada quando
 * desmarcada é exatamente a opacidade que esta tela existe para tirar do
 * caminho. Ela vai sempre no `accepted`, porque ela sempre acontece.
 */
const isDeclinable = proposal => !proposal.derived;

const label = id =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(
    `INBOX_WIDGET.PROFILE.PROPOSALS.${id.toUpperCase()}.${props.targetProfile.toUpperCase()}`
  );

const confirm = () =>
  emit(
    'confirm',
    proposals.value.filter(proposal => accepted.value.includes(proposal.id))
  );
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    :title="t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.TITLE')"
    :description="
      t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.DESCRIPTION', {
        profile: t(`INBOX_WIDGET.PROFILE.${targetProfile.toUpperCase()}.LABEL`),
      })
    "
    :confirm-button-label="t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.CONFIRM')"
    :cancel-button-label="t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.CANCEL')"
    @confirm="confirm"
    @close="emit('cancel')"
  >
    <div class="flex flex-col gap-4">
      <div v-if="proposals.length" class="flex flex-col gap-2">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.WILL_CHANGE') }}
        </h4>
        <template v-for="proposal in proposals" :key="proposal.id">
          <label
            v-if="isDeclinable(proposal)"
            class="flex items-start gap-2 text-sm cursor-pointer text-n-slate-11"
            :data-testid="`proposal-${proposal.id}`"
          >
            <input
              :id="`proposal-${proposal.id}`"
              type="checkbox"
              class="mt-1"
              :checked="accepted.includes(proposal.id)"
              @change="toggle(proposal.id)"
            />
            <span>{{ label(proposal.id) }}</span>
          </label>

          <p
            v-else
            class="flex items-start gap-2 text-sm text-n-slate-11"
            :data-testid="`proposal-${proposal.id}`"
          >
            <span aria-hidden="true" class="mt-1">•</span>
            <span>{{ label(proposal.id) }}</span>
          </p>
        </template>
      </div>

      <p v-else class="text-sm text-n-slate-11" data-testid="nothing-changes">
        {{ t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.NOTHING_CHANGES') }}
      </p>

      <div class="flex flex-col gap-1" data-testid="kept-values">
        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.WILL_KEEP') }}
        </h4>
        <p class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.PROFILE.SWITCH_DIALOG.KEEP_EXPLANATION') }}
        </p>
        <ul v-if="kept.length" class="pl-5 text-sm list-disc text-n-slate-11">
          <li v-for="proposal in kept" :key="proposal.id">
            {{ label(proposal.id) }}
          </li>
        </ul>
      </div>
    </div>
  </Dialog>
</template>
