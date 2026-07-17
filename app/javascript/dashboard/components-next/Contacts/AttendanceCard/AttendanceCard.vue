<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Card PRÓPRIO, não uma extensão do ContactsCard: aquele traz formulário de
// edição, seção de delete e checkbox de seleção — tudo de contato, e nada disso
// faz sentido num atendimento. Aqui NÃO entra nenhum trecho de conversa (D2): o
// endpoint nem envia.
const props = defineProps({
  // display_id da conversa (é o que a API de sub-recursos de conversa aceita).
  id: { type: Number, required: true },
  status: { type: String, default: 'open' },
  createdAt: { type: Number, default: null },
  lastActivityAt: { type: Number, default: null },
  contact: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  assignee: { type: Object, default: null },
  team: { type: Object, default: null },
  // Vem do BACKEND (mesma regra do endpoint de pedido): só é true quando este
  // usuário realmente pode solicitar esta conversa. Sem isto o botão apareceria
  // em conversas de outro time e o clique tomaria 403.
  canRequest: { type: Boolean, default: false },
  isRequesting: { type: Boolean, default: false },
});

const emit = defineEmits(['requestAttendance']);

const { t } = useI18n();

const isBotAssignee = computed(() => props.assignee?.type === 'agent_bot');

const assigneeName = computed(
  () =>
    props.assignee?.availableName ||
    props.assignee?.name ||
    t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ASSIGNEE')
);

const teamName = computed(
  () => props.team?.name || t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_TEAM')
);

// Mapa explícito em vez de montar `...STATUS.${status.toUpperCase()}`: chave
// concatenada em runtime some das ferramentas de extração/varredura de i18n, que
// não conseguem provar que as 3 chaves existem nos dois locales.
const STATUS_LABEL_KEYS = {
  open: 'CONTACTS_LAYOUT.IN_ATTENDANCE.STATUS.OPEN',
  pending: 'CONTACTS_LAYOUT.IN_ATTENDANCE.STATUS.PENDING',
  snoozed: 'CONTACTS_LAYOUT.IN_ATTENDANCE.STATUS.SNOOZED',
};

const statusLabel = computed(() => {
  const key = STATUS_LABEL_KEYS[props.status];
  return key ? t(key) : props.status;
});

// created_at ("aberto há") e last_activity_at são verdade; assignee_last_changed_at
// NÃO é "atendendo desde" — é zerado na primeira resposta do agente.
const openedAgo = computed(() =>
  props.createdAt ? dynamicTime(props.createdAt) : null
);
const lastActivityAgo = computed(() =>
  props.lastActivityAt ? dynamicTime(props.lastActivityAt) : null
);

const onRequestAttendance = () => {
  emit('requestAttendance', {
    conversationId: props.id,
    contactId: props.contact?.id,
  });
};
</script>

<template>
  <div
    class="flex flex-col w-full gap-3 p-4 border border-n-weak rounded-xl bg-n-solid-1 hover:shadow-sm transition-shadow sm:flex-row sm:items-center"
  >
    <div class="flex items-center flex-1 min-w-0 gap-3">
      <Avatar
        :name="contact.name || ''"
        :src="contact.thumbnail"
        :size="40"
        rounded-full
      />
      <div class="flex flex-col min-w-0 gap-1">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ contact.name }}
        </span>
        <span
          v-if="contact.phoneNumber || contact.email"
          class="text-xs truncate text-n-slate-11"
        >
          {{ contact.phoneNumber || contact.email }}
        </span>
      </div>
    </div>

    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <div class="flex items-center gap-1.5 min-w-0">
        <Avatar
          v-if="assignee"
          :name="assigneeName"
          :src="assignee.thumbnail"
          :size="16"
          rounded-full
        />
        <span
          class="text-sm truncate"
          :class="assignee ? 'text-n-slate-12' : 'text-n-slate-10 italic'"
        >
          {{ assigneeName }}
        </span>
        <span
          v-if="isBotAssignee"
          class="px-1.5 py-0.5 text-xs font-medium rounded shrink-0 bg-n-alpha-2 text-n-slate-11"
        >
          {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.AI_BADGE') }}
        </span>
      </div>
      <span
        class="text-xs truncate"
        :class="team ? 'text-n-slate-11' : 'text-n-slate-10 italic'"
      >
        {{ teamName }}
      </span>
    </div>

    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <span class="text-xs truncate text-n-slate-11">
        {{ inbox.name }}
      </span>
      <span class="text-xs truncate text-n-slate-11">
        {{ statusLabel }}
      </span>
    </div>

    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <span v-if="openedAgo" class="text-xs truncate text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.OPENED_AGO', { time: openedAgo }) }}
      </span>
      <span v-if="lastActivityAgo" class="text-xs truncate text-n-slate-10">
        {{
          t('CONTACTS_LAYOUT.IN_ATTENDANCE.LAST_ACTIVITY', {
            time: lastActivityAgo,
          })
        }}
      </span>
    </div>

    <div v-if="canRequest" class="shrink-0">
      <Button
        size="sm"
        variant="faded"
        color="slate"
        :is-loading="isRequesting"
        :disabled="isRequesting"
        :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST_ATTENDANCE')"
        @click="onRequestAttendance"
      />
    </div>
  </div>
</template>
