<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useGroupConversation } from 'dashboard/composables/useGroupConversation';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationMedia from './ConversationMedia.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import GroupParticipants from './GroupParticipants.vue';
import ContactInfo from './contact/ContactInfo.vue';
import SiteContext from './contact/SiteContext.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import KanbanStatus from './KanbanStatus.vue';
import MessageSequenceWidget from './MessageSequenceWidget.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import ConversationSummary from './ConversationSummary.vue';
import ConversationChecklist from './ConversationChecklist.vue';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const { t } = useI18n();

const {
  uiSettings,
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();

// "Mídias e Arquivos" abre por padrão (deixa o "Baixar todas" à vista de quem
// está no chat). Só fica recolhido se o usuário o tiver fechado de propósito.
const isMediaSectionOpen = computed(
  () => uiSettings.value?.is_conv_media_open !== false
);

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const macros = useMapGetter('macros/getMacros');
const hasMacros = computed(() => (macros.value || []).length > 0);
const conversationId = computed(() => props.conversationId);
const isSequencesOpen = ref(true);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

// A seção "Integrantes" só existe em conversa de grupo (WhatsApp/WAHA).
const { isGroup, participantCount, hasSnapshot } = useGroupConversation();

// Integrantes abre por padrão (é a informação que falta hoje em grupo); só fica
// recolhido se o agente o fechar de propósito — mesmo critério de "Mídias".
const isGroupParticipantsOpen = computed(
  () => uiSettings.value?.is_group_participants_open !== false
);

const groupParticipantsTitle = computed(() =>
  hasSnapshot.value && participantCount.value
    ? t('GROUP_INFO.SIDEBAR_TITLE_WITH_COUNT', {
        count: participantCount.value,
      })
    : t('GROUP_INFO.SIDEBAR_TITLE')
);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
// A store de contatos cameliza o payload da API
// (store/modules/contacts/mutations.js:5, camelcaseKeys deep), entao o registro
// guarda `additionalAttributes`. Ler so `additional_attributes` devolvia SEMPRE
// {} — e por isso a linha "Endereco IP" do painel nunca renderizava para
// ninguem. Aceita as duas formas: nem todo caminho passa pela store.
const contactAdditionalAttributes = computed(
  () =>
    contact.value.additionalAttributes ||
    contact.value.additional_attributes ||
    {}
);

// ── Bloco 5.23 — o que o site nos contou ──────────────────────────────────────────────
//
// TUDO abaixo já está na memória do painel: `custom_attributes` vêm no payload da conversa e
// do contato, e as definições (de onde saem os rótulos, já traduzidos pelo servidor) a store
// de atributos carrega para desenhar a lista de atributos personalizados. Nenhuma requisição
// nova — é reorganização do que já chega, que é o aceite do bloco.
//
// MEDIDO NA MUTATION REAL da store (`specs/siteContextStoreShape.spec.js`), não presumido pela
// forma do nome — que foi como o "Endereço IP" se perdeu no 1.17.
//
// O resultado surpreende e por isso está escrito aqui: `stopPaths: ['custom_attributes']`
// protege o CONTEÚDO (as chaves `first_utm_source` sobrevivem), mas **não a chave do topo** —
// ela vira `customAttributes` como qualquer outra. Então o registro guarda
// `contato.customAttributes.first_utm_source`: camelizado por fora, snake_case por dentro.
//
// Aceitamos as duas formas porque nem todo caminho passa pela store (o `meta.sender` do payload
// da conversa chega cru), e porque assim esta seção não depende de como o defeito irmão
// descrito no relatório for resolvido.
const contactCustomAttributes = computed(
  () =>
    contact.value?.customAttributes || contact.value?.custom_attributes || {}
);
// A store de CONVERSAS não cameliza o payload (só os filtros salvos), então aqui a chave é
// snake_case mesmo. A assimetria entre as duas stores é real e é a origem desta classe de bug.
const conversationCustomAttributes = computed(
  () =>
    currentChat.value?.custom_attributes ||
    currentChat.value?.customAttributes ||
    {}
);

const attributesByModel = useMapGetter('attributes/getAttributesByModel');
const originDefinitions = computed(() => [
  ...(attributesByModel.value('contact_attribute') || []),
  ...(attributesByModel.value('conversation_attribute') || []),
]);

// Bloco 4.15: o identificador que o site mandou, e se ele veio ASSINADO. Os dois já chegam —
// `hmac_verified` vem em `meta` (o `ConversationHeader` já o lê).
const siteIdentifier = computed(
  () => currentChat.value?.meta?.sender?.identifier || ''
);
const isHmacVerified = computed(() => !!currentChat.value?.meta?.hmac_verified);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  store.dispatch('macros/get');
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});
</script>

<template>
  <div class="w-full wa-contact-panel">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    />
    <ContactInfo :contact="contact" :channel-type="channelType" />
    <ConversationSummary />
    <ConversationChecklist />
    <div class="pb-8">
      <Draggable
        :list="conversationSidebarItems"
        animation="200"
        ghost-class="ghost"
        handle=".drag-handle"
        item-key="name"
        class="flex flex-col"
        @start="dragging = true"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <div
            v-if="element.name === 'conversation_media'"
            class="conversation--media"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MEDIA_AND_FILES')"
              :is-open="isMediaSectionOpen"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_media_open', value)
              "
            >
              <ConversationMedia :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'group_participants' && isGroup"
            class="conversation--group-participants"
          >
            <AccordionItem
              :title="groupParticipantsTitle"
              :is-open="isGroupParticipantsOpen"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_group_participants_open', value)
              "
            >
              <GroupParticipants :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'conversation_actions'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')"
              :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
              @toggle="
                value => toggleSidebarUIState('is_conv_actions_open', value)
              "
            >
              <ConversationAction
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'conversation_participants'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
              :is-open="isContactSidebarItemOpen('is_conv_participants_open')"
              @toggle="
                value =>
                  toggleSidebarUIState('is_conv_participants_open', value)
              "
            >
              <ConversationParticipant
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'conversation_info'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
              :is-open="isContactSidebarItemOpen('is_conv_details_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_details_open', value)
              "
            >
              <ConversationInfo
                :conversation-attributes="conversationAdditionalAttributes"
                :contact-attributes="contactAdditionalAttributes"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'site_context'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SITE_CONTEXT')"
              :is-open="isContactSidebarItemOpen('is_site_context_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_site_context_open', value)
              "
            >
              <SiteContext
                :contact-attributes="contactCustomAttributes"
                :conversation-attributes="conversationCustomAttributes"
                :definitions="originDefinitions"
                :identifier="siteIdentifier"
                :hmac-verified="isHmacVerified"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_attributes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
              :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_contact_attributes_open', value)
              "
            >
              <CustomAttributes
                attribute-type="contact_attribute"
                attribute-from="conversation_contact_panel"
                :contact-id="contact.id"
                :empty-state-message="
                  $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                "
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'previous_conversation'">
            <AccordionItem
              v-if="contact.id"
              :title="
                $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
              "
              :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_previous_conv_open', value)
              "
            >
              <ContactConversations
                :contact-id="contact.id"
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <woot-feature-toggle
            v-else-if="element.name === 'macros' && hasMacros"
            feature-key="macros"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
              :is-open="isContactSidebarItemOpen('is_macro_open')"
              compact
              @toggle="value => toggleSidebarUIState('is_macro_open', value)"
            >
              <MacrosList :conversation-id="conversationId" />
            </AccordionItem>
          </woot-feature-toggle>
          <div
            v-else-if="
              element.name === 'linear_issues' &&
              isLinearFeatureEnabled &&
              isLinearClientIdConfigured
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
              :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_linear_issues_open', value)
              "
            >
              <LinearSetupCTA v-if="!isLinearConnected" />
              <LinearIssuesList v-else :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'shopify_orders' && isShopifyFeatureEnabled
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
              :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shopify_orders_open', value)
              "
            >
              <ShopifyOrdersList :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_notes'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
              :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_contact_notes_open', value)
              "
            >
              <ContactNotes :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'kanban_status'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.KANBAN_STATUS')"
              :is-open="isContactSidebarItemOpen('is_kanban_status_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_kanban_status_open', value)
              "
            >
              <KanbanStatus :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'shared_files'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
              :is-open="isContactSidebarItemOpen('is_shared_files_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shared_files_open', value)
              "
            >
              <SharedFiles />
            </AccordionItem>
          </div>
        </template>
      </Draggable>
      <woot-feature-toggle feature-key="message_sequences">
        <AccordionItem
          :title="$t('CONVERSATION_SIDEBAR.MESSAGE_SEQUENCES.TITLE')"
          :is-open="isSequencesOpen"
          compact
          @toggle="value => (isSequencesOpen = value)"
        >
          <MessageSequenceWidget :conversation-id="conversationId" />
        </AccordionItem>
      </woot-feature-toggle>
    </div>
  </div>
</template>
