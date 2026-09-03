<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import WidgetProfileSwitchDialog from './WidgetProfileSwitchDialog.vue';
import {
  WIDGET_PROFILES,
  normalizeProfile,
} from './composables/useProfileVisibility';

/**
 * O seletor de perfil — o primeiro campo da aba, antes de qualquer outro.
 *
 * Não é uma aba própria de propósito: o perfil não é uma configuração entre
 * outras, ele determina QUAIS configurações existem. Precisa estar visível
 * antes das outras escolhas.
 *
 * Trocar não grava nada sozinho: abre o diálogo que lista o que muda.
 */
const props = defineProps({
  modelValue: { type: String, default: '' },
  /** O que já está gravado, para o diálogo não propor o que já é assim. */
  currentValues: { type: Object, default: () => ({}) },
  /** No wizard de criação não há nada gravado — e nada é pré-selecionado. */
  allowEmpty: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'apply']);

const { t } = useI18n();

const pendingProfile = ref('');
const isDialogOpen = ref(false);

const activeProfile = computed(() =>
  props.allowEmpty && !props.modelValue
    ? ''
    : normalizeProfile(props.modelValue)
);

const select = profile => {
  if (profile === activeProfile.value) return;

  // Inbox nova (regime 1): não há valor gravado para preservar, então a
  // escolha é direta. O diálogo só existe para a inbox que já roda.
  if (props.allowEmpty && !props.modelValue) {
    emit('update:modelValue', profile);
    return;
  }

  pendingProfile.value = profile;
  isDialogOpen.value = true;
};

const confirm = accepted => {
  isDialogOpen.value = false;
  emit('update:modelValue', pendingProfile.value);
  emit('apply', { profile: pendingProfile.value, accepted });
  pendingProfile.value = '';
};

const cancel = () => {
  isDialogOpen.value = false;
  pendingProfile.value = '';
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="grid gap-3 sm:grid-cols-2">
      <RadioCard
        v-for="profile in WIDGET_PROFILES"
        :id="profile"
        :key="profile"
        :label="t(`INBOX_WIDGET.PROFILE.${profile.toUpperCase()}.LABEL`)"
        :description="
          t(`INBOX_WIDGET.PROFILE.${profile.toUpperCase()}.DESCRIPTION`)
        "
        :is-active="activeProfile === profile"
        :data-testid="`profile-${profile}`"
        @select="select(profile)"
      />
    </div>

    <WidgetProfileSwitchDialog
      :open="isDialogOpen"
      :target-profile="pendingProfile || 'support'"
      :current-values="currentValues"
      @confirm="confirm"
      @cancel="cancel"
    />
  </div>
</template>
