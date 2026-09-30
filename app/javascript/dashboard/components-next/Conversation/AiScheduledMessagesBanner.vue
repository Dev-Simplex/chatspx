<script setup>
// CHAT-165: faixa com a mensagem que a IA agendou para esta conversa. A agendada sai mesmo com a
// conversa num humano, então quem atende precisa VER o que vai sair e poder cancelar.
// Só lista agendadas da IA (captain_assistant presente): quem não usa a agendada_mensagem não vê
// nada novo. Recarrega ao trocar de conversa e a cada mensagem nova, porque é num turno da IA que
// a agendada nasce, muda ou é cancelada.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';

const props = defineProps({
  conversationDisplayId: { type: Number, default: null },
  messagesCount: { type: Number, default: 0 },
});

const { t } = useI18n();
const agendadas = ref([]);
const cancelando = ref(null);

const carregar = async () => {
  if (!props.conversationDisplayId) {
    agendadas.value = [];
    return;
  }
  try {
    const { data } = await ScheduledMessagesAPI.getAiPendingByConversation(
      props.conversationDisplayId
    );
    agendadas.value = (data?.payload || data || []).filter(
      item => item.captain_assistant
    );
  } catch (error) {
    agendadas.value = [];
  }
};

const quando = value => {
  if (!value) return '';
  return new Date(value).toLocaleString([], {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const cancelar = async id => {
  cancelando.value = id;
  try {
    await ScheduledMessagesAPI.cancel(id);
    useAlert(t('CONVERSATION.AI_SCHEDULED_BANNER.CANCELLED'));
  } catch (error) {
    useAlert(t('CONVERSATION.AI_SCHEDULED_BANNER.CANCEL_ERROR'));
  } finally {
    cancelando.value = null;
    await carregar();
  }
};

watch(
  () => [props.conversationDisplayId, props.messagesCount],
  () => carregar(),
  { immediate: true }
);
</script>

<template>
  <div
    v-if="agendadas.length"
    class="flex flex-col gap-1 mx-2 mt-2 relative z-10"
  >
    <div
      v-for="item in agendadas"
      :key="item.id"
      data-testid="ai-scheduled-message"
      class="flex flex-col gap-2 px-3 py-2 border rounded-lg border-n-weak bg-n-alpha-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex items-center min-w-0 gap-2 text-sm text-n-slate-12">
        <span class="i-lucide-calendar-clock size-4 shrink-0 text-n-slate-11" />
        <span class="min-w-0">
          <span class="font-medium">
            {{
              t('CONVERSATION.AI_SCHEDULED_BANNER.TITLE', {
                name: item.captain_assistant.name,
                when: quando(item.scheduled_at),
              })
            }}
          </span>
          <span class="block truncate text-n-slate-11">{{ item.message }}</span>
        </span>
      </div>
      <Button
        size="sm"
        variant="ghost"
        color="ruby"
        class="shrink-0"
        :is-loading="cancelando === item.id"
        :label="t('CONVERSATION.AI_SCHEDULED_BANNER.CANCEL')"
        @click="cancelar(item.id)"
      />
    </div>
  </div>
</template>
