<script>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { mapGetters } from 'vuex';
import { createConsumer } from '@rails/actioncable';
import * as privateChatApi from 'dashboard/api/privateChat';
import MessageList from 'dashboard/components-next/message/MessageList.vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

const STORAGE_TOKEN_KEY = 'private_chat_token';
const STORAGE_CONVERSATION_ID_KEY = 'private_chat_conversation_id';

export default {
  name: 'PrivateChatView',
  components: { MessageList },
  setup() {
    const route = useRoute();
    const password = ref('');
    const token = ref(sessionStorage.getItem(STORAGE_TOKEN_KEY) || '');
    const conversationId = ref(
      sessionStorage.getItem(STORAGE_CONVERSATION_ID_KEY) || ''
    );
    const messages = ref([]);
    const loading = ref(false);
    const error = ref('');
    const sending = ref(false);
    const messageInput = ref('');
    let cableSubscription = null;

    const accountId = computed(() => route.params.accountId);

    const isUnlocked = computed(() => !!token.value);

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
          },
        }
      );
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
      messageInput,
      isUnlocked,
      accountId,
      unlock,
      loadMessages,
      sendMessage,
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
        class="flex shrink-0 items-center border-b border-n-200 px-4 py-3"
      >
        <h1 class="text-lg font-medium text-n-900">Notas</h1>
      </header>
      <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
        <div
          v-if="loading && messages.length === 0"
          class="flex flex-1 items-center justify-center p-4"
        >
          <span class="text-n-600">Carregando...</span>
        </div>
        <div v-else class="flex-1 overflow-y-auto p-4">
          <MessageList
            :messages="messages"
            :current-user-id="currentUserId"
          />
        </div>
        <div
          class="flex shrink-0 gap-2 border-t border-n-200 bg-n-50 p-3"
        >
          <input
            v-model="messageInput"
            type="text"
            class="min-w-0 flex-1 rounded border border-n-200 bg-white px-3 py-2 text-n-900"
            placeholder="Digite uma mensagem..."
            :disabled="sending"
            @keydown.enter.prevent="sendMessage"
          />
          <button
            type="button"
            class="rounded bg-s-500 px-4 py-2 text-white hover:bg-s-600 disabled:opacity-50"
            :disabled="sending || !messageInput?.trim()"
            @click="sendMessage"
          >
            Enviar
          </button>
        </div>
      </div>
      <p v-if="error" class="px-4 py-2 text-sm text-r-500">{{ error }}</p>
    </template>
  </div>
</template>
