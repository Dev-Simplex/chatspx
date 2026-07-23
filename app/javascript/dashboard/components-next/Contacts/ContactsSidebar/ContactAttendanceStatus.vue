<script setup>
// Aba "Andamento" da página de contato: quem está atendendo este contato AGORA
// (agente, time, caixa, status, há quanto tempo). Read-only — as ações moram no
// header. Substitui a aba "Notas" (que segue disponível dentro das conversas).
//
// Dados vêm do pai (useContactAttendance → endpoint da Fase 1, cross-team). NÃO
// usa contactConversations, que é cego a atendimento de outro time.
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  attendances: { type: Array, default: () => [] },
  isFetching: { type: Boolean, default: false },
});

const { t } = useI18n();
const currentUserId = useMapGetter('getCurrentUserID');

const isBot = a => a.assignee?.type === 'agent_bot';
const isMine = a =>
  a.assignee?.type === 'user' && a.assignee.id === currentUserId.value;

const assigneeName = a =>
  a.assignee?.availableName ||
  a.assignee?.name ||
  t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ASSIGNEE');
</script>

<template>
  <div class="px-6 py-4">
    <div
      v-if="isFetching"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>

    <div
      v-else-if="!attendances.length"
      class="flex items-center justify-center py-10 text-center"
    >
      <span class="text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACTIVE_ATTENDANCE') }}
      </span>
    </div>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="attendance in attendances"
        :key="attendance.id"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center gap-2 min-w-0">
          <Avatar
            v-if="attendance.assignee"
            :name="assigneeName(attendance)"
            :src="attendance.assignee.thumbnail"
            :size="20"
            rounded-full
          />
          <span
            class="text-sm truncate"
            :class="
              attendance.assignee ? 'text-n-slate-12' : 'text-n-slate-10 italic'
            "
          >
            {{ assigneeName(attendance) }}
          </span>
          <span
            v-if="isMine(attendance)"
            class="px-1.5 py-0.5 text-xs font-medium rounded shrink-0 bg-n-teal-3 text-n-teal-11"
          >
            {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.YOU') }}
          </span>
          <span
            v-else-if="isBot(attendance)"
            class="px-1.5 py-0.5 text-xs font-medium rounded shrink-0 bg-n-alpha-2 text-n-slate-11"
          >
            {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.AI_BADGE') }}
          </span>
        </div>

        <div
          class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-n-slate-11"
        >
          <span>{{
            attendance.team?.name || t('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_TEAM')
          }}</span>
          <span class="text-n-slate-6">·</span>
          <span>{{ attendance.inbox?.name }}</span>
          <span v-if="attendance.createdAt" class="text-n-slate-6">·</span>
          <span v-if="attendance.createdAt">
            {{
              t('CONTACTS_LAYOUT.IN_ATTENDANCE.OPENED_AGO', {
                time: dynamicTime(attendance.createdAt),
              })
            }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
