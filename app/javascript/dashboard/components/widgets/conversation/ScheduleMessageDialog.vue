<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  inboxId: { type: [Number, String], default: null },
  // necessário para agendar em OUTRA caixa: o backend só honra a caixa escolhida
  // quando recebe contact_id + inbox_id (com conversation_id ele usa a caixa da
  // própria conversa e ignora a escolha).
  contactId: { type: [Number, String], default: null },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const dialogRef = ref(null);
const templateParserRef = ref(null);

const inboxesList = useMapGetter('inboxes/getInboxes');
const templatesFor = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

const toLocalInputValue = date => {
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const selectedInboxId = ref(props.inboxId ? Number(props.inboxId) : null);
// Já nasce com uma hora à frente. Campo obrigatório vazio + botão desabilitado
// sem explicação faz o agente achar que a tela travou — principalmente porque o
// campo de data fica acima da dobra depois que o bloco de template aparece.
const scheduledAt = ref(
  toLocalInputValue(new Date(Date.now() + 60 * 60 * 1000))
);
const messageText = ref('');
const selectedTemplateName = ref('');
const isSaving = ref(false);
const scheduled = ref([]);
const isLoadingList = ref(false);

const selectedInbox = computed(() =>
  (inboxesList.value || []).find(i => Number(i.id) === selectedInboxId.value)
);

// Só o canal Oficial (Cloud API) tem HSM. WAHA (Channel::Api) manda texto puro,
// então lá o template nem entra em cena.
const isOfficialWhatsapp = computed(
  () => selectedInbox.value?.channel_type === INBOX_TYPES.WHATSAPP
);

const templates = computed(() =>
  selectedInboxId.value ? templatesFor.value(selectedInboxId.value) || [] : []
);

const selectedTemplate = computed(() =>
  templates.value.find(tpl => tpl.name === selectedTemplateName.value)
);

// Decisão do usuário: no WhatsApp Oficial o agendamento EXIGE template. Fora da
// janela de 24h só template é entregue, e na hora de agendar não dá para saber
// se a janela estará aberta lá na frente.
const requiresTemplate = computed(() => isOfficialWhatsapp.value);

const hasNoTemplates = computed(
  () => requiresTemplate.value && templates.value.length === 0
);

const minDateTime = computed(() => {
  const d = new Date(Date.now() + 60 * 1000);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
});

// Diz O QUE falta. Botão desabilitado mudo é o que fez o agente achar que a tela
// tinha quebrado, já que o campo pendente costuma estar fora da área visível.
const missingReason = computed(() => {
  if (!selectedInboxId.value)
    return t('CONVERSATION.SCHEDULE_MESSAGE.MISSING.INBOX');
  if (!scheduledAt.value)
    return t('CONVERSATION.SCHEDULE_MESSAGE.MISSING.WHEN');
  if (new Date(scheduledAt.value).getTime() <= Date.now()) {
    return t('CONVERSATION.SCHEDULE_MESSAGE.MISSING.PAST');
  }
  if (requiresTemplate.value && !selectedTemplate.value) {
    return t('CONVERSATION.SCHEDULE_MESSAGE.MISSING.TEMPLATE');
  }
  if (!requiresTemplate.value && !messageText.value.trim()) {
    return t('CONVERSATION.SCHEDULE_MESSAGE.MISSING.MESSAGE');
  }
  return '';
});

const isValid = computed(() => !missingReason.value);

const loadScheduled = async () => {
  isLoadingList.value = true;
  try {
    const { data } = await ScheduledMessagesAPI.getByConversation(
      props.conversationId
    );
    scheduled.value = data?.payload || data || [];
  } catch (error) {
    scheduled.value = [];
  } finally {
    isLoadingList.value = false;
  }
};

// Mudou de caixa: o agendamento não pertence mais a ESTA conversa, e sim à
// conversa do mesmo contato naquela outra caixa (o backend acha ou cria). Mandar
// conversation_id aqui faria o backend usar a caixa da conversa e descartar a
// escolha em silêncio.
const isOtherInbox = computed(
  () => Number(selectedInboxId.value) !== Number(props.inboxId)
);

const buildPayload = () => {
  const payload = {
    inbox_id: selectedInboxId.value,
    scheduled_at: new Date(scheduledAt.value).toISOString(),
  };

  if (isOtherInbox.value && props.contactId) {
    payload.contact_id = props.contactId;
  } else {
    payload.conversation_id = props.conversationId;
  }

  if (!requiresTemplate.value) {
    payload.message = messageText.value.trim();
    return payload;
  }

  const parser = templateParserRef.value;
  const tpl = selectedTemplate.value;
  // O corpo renderizado vira o `message`: a coluna é NOT NULL e é esse texto que
  // o agente vê na listagem. Os parâmetros seguem em template_params, que é o que
  // o SendService repassa como HSM.
  payload.message = parser?.renderedTemplate || tpl?.name || '';
  payload.template_params = {
    name: tpl?.name || '',
    namespace: tpl?.namespace || '',
    category: tpl?.category || 'UTILITY',
    language: tpl?.language || 'pt_BR',
    processed_params: parser?.processedParams || {},
  };
  return payload;
};

const submit = async () => {
  if (!isValid.value || isSaving.value) return;

  if (requiresTemplate.value && templateParserRef.value?.v$) {
    const parserValidation = templateParserRef.value.v$;
    parserValidation.$touch();
    if (parserValidation.$invalid) {
      useAlert(t('CONVERSATION.SCHEDULE_MESSAGE.ERRORS.TEMPLATE_INCOMPLETE'));
      return;
    }
  }

  isSaving.value = true;
  try {
    await ScheduledMessagesAPI.create(buildPayload());
    useAlert(t('CONVERSATION.SCHEDULE_MESSAGE.API.SUCCESS'));
    messageText.value = '';
    selectedTemplateName.value = '';
    // volta ao padrão em vez de zerar: campo obrigatório vazio é justamente o que
    // fazia o botão desabilitar sem explicação.
    scheduledAt.value = toLocalInputValue(
      new Date(Date.now() + 60 * 60 * 1000)
    );
    await loadScheduled();
  } catch (error) {
    const apiError = error?.response?.data?.error;
    useAlert(apiError || t('CONVERSATION.SCHEDULE_MESSAGE.API.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const cancelScheduled = async id => {
  try {
    await ScheduledMessagesAPI.cancel(id);
    useAlert(t('CONVERSATION.SCHEDULE_MESSAGE.API.CANCELLED'));
    await loadScheduled();
  } catch (error) {
    useAlert(t('CONVERSATION.SCHEDULE_MESSAGE.API.CANCEL_ERROR'));
  }
};

const formatWhen = value => {
  if (!value) return '';
  try {
    return new Date(value).toLocaleString();
  } catch (error) {
    return value;
  }
};

onMounted(() => {
  // Dialog nativo: sem open() ele não aparece.
  dialogRef.value?.open();
  loadScheduled();
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    full-height
    :title="t('CONVERSATION.SCHEDULE_MESSAGE.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4 min-h-0 flex-1 overflow-y-auto">
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.INBOX') }}
        </label>
        <select v-model.number="selectedInboxId" class="!mb-0 text-sm">
          <option
            v-for="inbox in inboxesList"
            :key="inbox.id"
            :value="inbox.id"
          >
            {{ inbox.name }}
          </option>
        </select>
        <p class="mt-1 mb-0 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.INBOX_HINT') }}
        </p>
        <p v-if="isOtherInbox" class="mt-1 mb-0 text-xs text-n-amber-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.OTHER_INBOX_WARNING') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.WHEN') }}
        </label>
        <input
          v-model="scheduledAt"
          type="datetime-local"
          class="!mb-0 text-sm"
          :min="minDateTime"
        />
      </div>

      <!-- WhatsApp Oficial: fora da janela de 24h só template entrega, e no
           agendamento não dá pra saber se ela estará aberta. Por isso é exigido. -->
      <div v-if="requiresTemplate" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.TEMPLATE') }}
        </label>
        <p class="mt-0 mb-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.TEMPLATE_REQUIRED_HINT') }}
        </p>
        <p v-if="hasNoTemplates" class="mb-0 text-sm text-n-amber-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.NO_TEMPLATES') }}
        </p>
        <select v-else v-model="selectedTemplateName" class="!mb-0 text-sm">
          <option value="">
            {{ t('CONVERSATION.SCHEDULE_MESSAGE.TEMPLATE_PLACEHOLDER') }}
          </option>
          <option
            v-for="tpl in templates"
            :key="tpl.id || tpl.name"
            :value="tpl.name"
          >
            {{ tpl.name }}
          </option>
        </select>
        <WhatsAppTemplateParser
          v-if="selectedTemplate"
          ref="templateParserRef"
          :key="selectedTemplateName"
          :template="selectedTemplate"
          class="mt-2"
        />
      </div>

      <div v-else class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.MESSAGE') }}
        </label>
        <textarea
          v-model="messageText"
          rows="4"
          class="reset-base w-full px-3 py-2 text-sm rounded-lg resize-none bg-n-alpha-2 border border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
          :placeholder="t('CONVERSATION.SCHEDULE_MESSAGE.MESSAGE_PLACEHOLDER')"
        />
      </div>

      <div class="pt-4 border-t border-n-weak">
        <h4 class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.PENDING_TITLE') }}
        </h4>
        <p v-if="isLoadingList" class="mb-0 text-sm text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.LOADING') }}
        </p>
        <p v-else-if="!scheduled.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE_MESSAGE.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2 m-0 list-none">
          <li
            v-for="item in scheduled"
            :key="item.id"
            class="flex items-start gap-3 p-2 rounded-lg bg-n-alpha-1"
          >
            <div class="flex flex-col min-w-0 grow">
              <span class="text-xs text-n-slate-11">
                {{ formatWhen(item.scheduled_at || item.scheduledAt) }}
              </span>
              <span class="text-sm truncate text-n-slate-12">
                {{ item.message }}
              </span>
            </div>
            <Button
              type="button"
              variant="ghost"
              color="ruby"
              size="sm"
              :label="t('CONVERSATION.SCHEDULE_MESSAGE.CANCEL_ITEM')"
              @click="cancelScheduled(item.id)"
            />
          </li>
        </ul>
      </div>
    </div>

    <!-- Rodapé fixo: o botão não pode viver dentro da área que rola, senão fica
         fora da vista justamente quando o bloco de template estica o formulário. -->
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <p class="mb-0 text-xs text-n-amber-11">
          {{ missingReason }}
        </p>
        <Button
          type="button"
          class="flex-shrink-0"
          :label="t('CONVERSATION.SCHEDULE_MESSAGE.SUBMIT')"
          :disabled="!isValid || isSaving"
          :is-loading="isSaving"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
