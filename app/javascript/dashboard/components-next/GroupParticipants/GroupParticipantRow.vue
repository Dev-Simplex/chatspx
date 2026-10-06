<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { authorColor } from 'dashboard/helper/whatsappGroupHelper';

const props = defineProps({
  /**
   * Participante já normalizado por `useGroupConversation`:
   * { key, lid, phone, name, admin, label, isUnknown, formattedPhone }
   */
  participant: {
    type: Object,
    required: true,
  },
  isActive: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['select']);

const { t } = useI18n();

/**
 * Cor determinística do participante — a mesma que a bolha usa para o autor,
 * o que amarra visualmente o painel e o fio. O LID entra só como chave de hash;
 * ele nunca é renderizado (regra inviolável do briefing).
 */
const accent = computed(() => {
  if (props.participant.isUnknown) {
    return {
      bg: '#8696a0',
      text: '#ffffff',
      darkBg: '#54656f',
      darkText: '#e9edef',
    };
  }
  return {
    bg: authorColor(props.participant, false),
    text: '#ffffff',
    darkBg: authorColor(props.participant, true),
    darkText: '#0b141a',
  };
});

/** Sem nome, o telefone formatado sobe para a linha principal. */
const primaryLine = computed(() => {
  const { isUnknown, name, formattedPhone } = props.participant;
  if (isUnknown) return '';
  return name || formattedPhone;
});

const secondaryLine = computed(() => {
  const { isUnknown, name, formattedPhone } = props.participant;
  if (isUnknown) return '—';
  if (name) return formattedPhone || '—';
  // Só número: diz por quê, para o agente saber que dá para salvar o contato.
  if (props.participant.notSaved) return t('GROUP_INFO.NOT_SAVED');
  if (props.participant.savedWithoutName) return t('GROUP_INFO.SAVED_NO_NAME');
  return '';
});

// Sem nome, o avatar mostra o ícone de pessoa em vez de "+5" (o início do número).
const avatarName = computed(() => {
  if (props.participant.isUnknown) return '?';
  return props.participant.name || '';
});
</script>

<template>
  <button
    type="button"
    class="flex items-center w-full gap-2.5 px-4 py-2 text-left transition-colors border-0 bg-transparent hover:bg-n-slate-3/40"
    :class="{ 'bg-n-slate-3/50': isActive }"
    :data-participant-lid="participant.lid || undefined"
    @click.stop="$emit('select', $event.currentTarget)"
  >
    <Avatar
      :name="avatarName"
      :size="32"
      :accent="accent"
      rounded-full
      class="flex-shrink-0"
    />
    <div class="flex-1 min-w-0">
      <div
        class="text-[13.5px] leading-tight truncate"
        :class="
          participant.isUnknown
            ? 'italic font-normal text-n-slate-11'
            : 'font-medium text-n-slate-12'
        "
      >
        {{
          participant.isUnknown
            ? $t('GROUP_INFO.UNKNOWN_PARTICIPANT')
            : primaryLine
        }}
      </div>
      <div
        v-if="secondaryLine"
        class="text-[12px] leading-tight truncate text-n-slate-11 tabular-nums"
      >
        {{ secondaryLine }}
      </div>
    </div>
    <span
      v-if="participant.isUnknown"
      v-tooltip="$t('GROUP_INFO.UNKNOWN_PARTICIPANT_HINT')"
      class="i-lucide-info size-3.5 flex-shrink-0 text-n-slate-10"
    />
    <span
      v-if="participant.admin"
      class="flex-shrink-0 px-[5px] py-px text-[10px] font-semibold tracking-wide uppercase border rounded text-n-teal-11 border-current"
    >
      {{ $t('GROUP_INFO.ADMIN_BADGE') }}
    </span>
  </button>
</template>
