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
  // Capacidades vindas do BACKEND (mesma regra que ele aplica de verdade). Sem
  // isto o botão prometeria uma ação que viraria 403/422 no clique.
  canOpen: { type: Boolean, default: false },
  canAssume: { type: Boolean, default: false },
  canRequest: { type: Boolean, default: false },
  // id do MEU pedido pendente nesta conversa (se houver) → "Pedido enviado · Cancelar".
  myPendingRequestId: { type: Number, default: null },
  // contato com 2+ atendimentos abertos ao mesmo tempo.
  duplicated: { type: Boolean, default: false },
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits([
  'openConversation',
  'assumeAttendance',
  'requestAttendance',
  'cancelRequest',
]);

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

// UMA ação por linha, decidida aqui (fonte única) — o template não repete
// condição. A ordem importa: "já pedi" vence "posso pedir".
const rowAction = computed(() => {
  if (props.myPendingRequestId) return 'pending';
  if (props.canAssume) return 'assume';
  if (props.canRequest) return 'request';
  if (props.canOpen) return 'open';
  return 'blocked';
});

// Por que a linha está muda: quase sempre é time do qual não participo.
const blockedReason = computed(() =>
  props.team?.name
    ? t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACCESS_TEAM', {
        team: props.team.name,
      })
    : t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACCESS_INBOX')
);

const payload = () => ({
  conversationId: props.id,
  contactId: props.contact?.id,
});

const onOpen = () => emit('openConversation', payload());
const onAssume = () => emit('assumeAttendance', payload());
const onRequest = () => emit('requestAttendance', payload());
const onCancel = () =>
  emit('cancelRequest', { ...payload(), requestId: props.myPendingRequestId });
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
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ contact.name }}
          </span>
          <!-- O sintoma que a feature existe p/ matar: mesmo contato em 2+
               atendimentos ABERTOS ao mesmo tempo. -->
          <span
            v-if="duplicated"
            class="px-1.5 py-0.5 text-xs font-medium rounded shrink-0 bg-n-amber-3 text-n-amber-11"
            :title="t('CONTACTS_LAYOUT.IN_ATTENDANCE.DUPLICATED_HINT')"
          >
            {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.DUPLICATED') }}
          </span>
        </div>
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

    <!-- UMA ação por linha (rowAction decide). A linha sem acesso não some: ela
         explica o porquê, porque a ciência da duplicação é metade do valor da aba. -->
    <div class="shrink-0 flex items-center gap-2">
      <template v-if="rowAction === 'pending'">
        <span class="text-xs text-n-slate-11">
          {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.PENDING_STATE') }}
        </span>
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          :is-loading="isBusy"
          :disabled="isBusy"
          :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.CANCEL')"
          @click="onCancel"
        />
      </template>
      <Button
        v-else-if="rowAction === 'assume'"
        size="sm"
        color="blue"
        :is-loading="isBusy"
        :disabled="isBusy"
        :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.ASSUME')"
        @click="onAssume"
      />
      <Button
        v-else-if="rowAction === 'request'"
        size="sm"
        variant="faded"
        color="slate"
        :is-loading="isBusy"
        :disabled="isBusy"
        :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST_ATTENDANCE')"
        @click="onRequest"
      />
      <Button
        v-else-if="rowAction === 'open'"
        size="sm"
        variant="faded"
        color="slate"
        :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.OPEN')"
        @click="onOpen"
      />
      <span v-else class="text-xs italic text-n-slate-10 text-right max-w-40">
        {{ blockedReason }}
      </span>
    </div>
  </div>
</template>
