<script>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { mapGetters } from 'vuex';
import { useToggle } from '@vueuse/core';
import { createConsumer } from '@rails/actioncable';
import { useI18n } from 'vue-i18n';
import * as privateChatApi from 'dashboard/api/privateChat';
import MessageList from 'dashboard/components-next/message/MessageList.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

const STORAGE_TOKEN_KEY = 'private_chat_token';
const STORAGE_CONVERSATION_ID_KEY = 'private_chat_conversation_id';

export default {
  name: 'PrivateChatView',
  components: { MessageList, ButtonV4, DropdownMenu },
  setup() {
    const route = useRoute();
    const { t } = useI18n();
    const [showActionsDropdown, toggleDropdown] = useToggle(false);
    const password = ref('');
    const token = ref(sessionStorage.getItem(STORAGE_TOKEN_KEY) || '');
    const conversationId = ref(
      sessionStorage.getItem(STORAGE_CONVERSATION_ID_KEY) || ''
    );
    const messages = ref([]);
    const loading = ref(false);
    const error = ref('');
    const sending = ref(false);
    const clearing = ref(false);
    const messageInput = ref('');
    const clearConfirmRef = ref(null);
    let cableSubscription = null;

    const accountId = computed(() => route.params.accountId);

    const isUnlocked = computed(() => !!token.value);

    const headerMenuItems = computed(() => [
      {
        icon: 'i-lucide-trash-2',
        label: t('NOTESPAD.CLEAR_CONVERSATION'),
        action: 'clear',
        value: 'clear',
      },
    ]);

    const normalizedMessages = computed(() => {
      return useCamelCase(messages.value, {
        deep: true,
        stopPaths: ['content_attributes.translations'],
      });
    });

    const loadMessages = async () => {
      if (!token.value || !accountId.value) return;
      loading.value = true;
      error.value = '';
      try {
        const { data } = await privateChatApi.getMessages(accountId.value, token.value);
        messages.value = data.payload || [];
      } catch (e) {
        if (e.response && e.response.status === 401) {
          token.value = '';
          conversationId.value = '';
          sessionStorage.removeItem(STORAGE_TOKEN_KEY);
          sessionStorage.removeItem(STORAGE_CONVERSATION_ID_KEY);
          if (cableSubscription) {
            cableSubscription.unsubscribe();
            cableSubscription = null;
          }
        } else if (e.response && e.response.status === 404) {
          token.value = '';
          conversationId.value = '';
          sessionStorage.removeItem(STORAGE_TOKEN_KEY);
          sessionStorage.removeItem(STORAGE_CONVERSATION_ID_KEY);
          if (cableSubscription) {
            cableSubscription.unsubscribe();
            cableSubscription = null;
          }
          error.value = '';
        } else {
          error.value = e.response?.data?.error || 'Erro ao carregar mensagens';
        }
      } finally {
        loading.value = false;
      }
    };

    const unlock = async () => {
      if (!password.value.trim()) return;
      loading.value = true;
      error.value = '';
      try {
        const { data } = await privateChatApi.unlock(
          accountId.value,
          (password.value || '').trim()
        );
        token.value = data.token;
        conversationId.value = String(data.conversation_id || '');
        sessionStorage.setItem(STORAGE_TOKEN_KEY, data.token);
        sessionStorage.setItem(STORAGE_CONVERSATION_ID_KEY, conversationId.value);
        password.value = '';
        await loadMessages();
        subscribeCable();
      } catch (e) {
        error.value =
          e.response?.data?.error || 'Senha inválida. Tente novamente.';
      } finally {
        loading.value = false;
      }
    };

    const subscribeCable = () => {
      if (!token.value || cableSubscription) return;
      const { websocketURL = '' } = window.chatwootConfig || {};
      const url = websocketURL ? `${websocketURL}/cable` : undefined;
      const consumer = createConsumer(url);
      cableSubscription = consumer.subscriptions.create(
        { channel: 'PrivateChatChannel', token: token.value },
        {
          received(data) {
            if (data?.event === 'message.created' && data?.message) {
              const msg = data.message;
              if (!messages.value.find(m => m.id === msg.id)) {
                messages.value = [...messages.value, msg];
              }
            }
            if (data?.event === 'conversation.cleared') {
              messages.value = [];
            }
          },
        }
      );
    };

    const clearConversation = async () => {
      if (!token.value || !accountId.value || clearing.value) return;
      clearing.value = true;
      error.value = '';
      try {
        await privateChatApi.clearMessages(accountId.value, token.value);
        messages.value = [];
      } catch (e) {
        if (e.response && e.response.status === 401) {
          token.value = '';
          sessionStorage.removeItem(STORAGE_TOKEN_KEY);
          sessionStorage.removeItem(STORAGE_CONVERSATION_ID_KEY);
        } else {
          error.value = e.response?.data?.error || 'Erro ao limpar conversa';
        }
      } finally {
        clearing.value = false;
      }
    };

    const onHeaderAction = async ({ action }) => {
      if (action === 'clear') {
        toggleDropdown(false);
        const confirmed = await clearConfirmRef.value?.showConfirmation?.();
        if (!confirmed) return;
        await clearConversation();
      }
    };

    const sendMessage = async () => {
      const content = (messageInput.value || '').trim();
      if (!content || !token.value || sending.value) return;
      sending.value = true;
      try {
        const { data } = await privateChatApi.createMessage(
          accountId.value,
          token.value,
          { content }
        );
        messageInput.value = '';
        if (data && data.id && !messages.value.find(m => m.id === data.id)) {
          messages.value = [...messages.value, data];
        }
      } catch (e) {
        if (e.response && e.response.status === 401) {
          token.value = '';
          sessionStorage.removeItem(STORAGE_TOKEN_KEY);
          sessionStorage.removeItem(STORAGE_CONVERSATION_ID_KEY);
        }
        error.value = e.response?.data?.error || 'Erro ao enviar';
      } finally {
        sending.value = false;
      }
    };

    watch(accountId, (newId, oldId) => {
      if (oldId != null && String(newId) !== String(oldId)) {
        token.value = '';
        conversationId.value = '';
        sessionStorage.removeItem(STORAGE_TOKEN_KEY);
        sessionStorage.removeItem(STORAGE_CONVERSATION_ID_KEY);
        if (cableSubscription) {
          cableSubscription.unsubscribe();
          cableSubscription = null;
        }
      }
    });

    onMounted(() => {
      if (token.value) {
        loadMessages();
        subscribeCable();
      }
    });

    onUnmounted(() => {
      if (cableSubscription) {
        cableSubscription.unsubscribe();
        cableSubscription = null;
      }
    });

    return {
      password,
      token,
      messages: normalizedMessages,
      loading,
      error,
      sending,
      clearing,
      messageInput,
      isUnlocked,
      accountId,
      showActionsDropdown,
      toggleDropdown,
      headerMenuItems,
      unlock,
      loadMessages,
      sendMessage,
      clearConversation,
      onHeaderAction,
      clearConfirmRef,
    };
  },
  computed: {
    ...mapGetters({ currentUserId: 'getCurrentUserID' }),
  },
};
</script>

<template>
  <div
    class="conversation-details-wrap flex flex-col min-w-0 w-full bg-n-background relative h-full"
  >
    <template v-if="!isUnlocked">
      <div
        class="flex flex-1 items-center justify-center p-4"
        style="min-height: 20rem"
      >
        <div class="w-full max-w-sm rounded-lg border border-n-200 bg-n-50 p-4">
          <label class="mb-2 block text-sm font-medium text-n-700">
            Acesso
          </label>
          <input
            v-model="password"
            type="password"
            class="w-full rounded border border-n-200 px-3 py-2 text-n-900"
            placeholder="Senha"
            autocomplete="off"
            @keydown.enter="unlock"
          />
          <p v-if="error" class="mt-2 text-sm text-r-500">{{ error }}</p>
          <button
            type="button"
            class="mt-3 w-full rounded bg-s-500 px-3 py-2 text-white hover:bg-s-600"
            :disabled="loading"
            @click="unlock"
          >
            {{ loading ? 'Entrando...' : 'Entrar' }}
          </button>
        </div>
      </div>
    </template>
    <template v-else>
      <header
        class="flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 py-2 border-b bg-n-background border-n-weak h-24 xl:h-12 shrink-0"
      >
        <div class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1">
          <span class="text-sm font-medium truncate leading-tight text-n-slate-12">
            Notas
          </span>
        </div>
        <div
          v-on-clickaway="() => toggleDropdown(false)"
          class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto relative"
        >
          <ButtonV4
            v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-more-vertical"
            class="rounded-md hover:bg-n-alpha-2"
            :disabled="clearing"
            @click="toggleDropdown()"
          />
          <DropdownMenu
            v-if="showActionsDropdown"
            :menu-items="headerMenuItems"
            class="mt-1 ltr:right-0 rtl:left-0 top-full absolute"
            @action="onHeaderAction"
          />
        </div>
      </header>
      <div class="flex flex-col justify-between flex-grow h-full min-w-0 m-0 min-h-0">
        <div
          v-if="loading && messages.length === 0"
          class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center justify-center max-w-full p-4"
        >
          <span class="text-n-600">Carregando...</span>
        </div>
        <MessageList
          v-else
          class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 pb-4 conversation-panel-light"
          :messages="messages"
          :current-user-id="currentUserId"
        />
        <div
          class="flex relative flex-col bg-n-background -mt-px border-t border-n-weak"
        >
          <div class="relative z-10 flex gap-2 py-1 px-3 min-h-[2.75rem] items-center mx-2 mb-2 rounded-3xl bg-[#e9edef] dark:bg-[#2d2d2d]">
            <input
              v-model="messageInput"
              type="text"
              class="min-w-0 flex-1 rounded border-0 bg-transparent px-2 py-2 text-n-900 dark:text-n-slate-12 focus:outline-none focus:ring-0 text-sm"
              placeholder="Digite uma mensagem..."
              :disabled="sending"
              @keydown.enter.prevent="sendMessage"
            />
            <button
              type="button"
              class="rounded-full bg-woot-500 hover:bg-woot-600 px-4 py-2 text-white disabled:opacity-50 flex-shrink-0 text-sm font-medium"
              :disabled="sending || !messageInput?.trim()"
              @click="sendMessage"
            >
              Enviar
            </button>
          </div>
        </div>
      </div>
      <p v-if="error" class="px-4 py-2 text-sm text-r-500 shrink-0">{{ error }}</p>
      <woot-confirm-modal
        ref="clearConfirmRef"
        :title="$t('NOTESPAD.CLEAR_CONVERSATION')"
        :description="$t('NOTESPAD.CLEAR_CONVERSATION_CONFIRM')"
        :confirm-label="$t('NOTESPAD.CONFIRM_CLEAR')"
        :cancel-label="$t('GENERAL.CLOSE')"
      />
    </template>
  </div>
</template>
