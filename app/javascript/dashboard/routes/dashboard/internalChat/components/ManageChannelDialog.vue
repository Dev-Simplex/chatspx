<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  channel: { type: Object, default: null },
  currentUserId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'askLeave']);

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);
const nameRef = ref(null);
// Dica dentro do <dialog> modal: nasce dentro dele, senão fica atrás (camada
// do topo do navegador) e não aparece.
const tip = content => ({ content, container: 'dialog[open]' });
// Botão "Remover" da confirmação já com o foco (Enter confirma).
const vFocusOnMount = { mounted: el => el.focus() };

const name = ref('');
const isSaving = ref(false);
const agentsLoading = ref(false);
const addQuery = ref('');
// Remover pede confirmação na própria linha; busy = id em andamento.
const confirmRemoveId = ref(null);
const busyId = ref(null);
// Retorno das ações DENTRO da janela: o aviso flutuante do app nasce atrás do
// <dialog> modal (camada do topo) e ficava ilegível, borrado pelo fundo.
const notice = ref(null); // { text, error }
let noticeTimer = null;
const say = (text, error = false) => {
  clearTimeout(noticeTimer);
  notice.value = { text, error };
  noticeTimer = setTimeout(() => {
    notice.value = null;
  }, 4000);
};

const isMe = member => Number(member.id) === Number(props.currentUserId);
// Você primeiro (marcado "você"); sair é pelo botão "Sair do grupo".
const members = computed(() =>
  [...(props.channel?.members || [])].sort((a, b) => isMe(b) - isMe(a))
);
const allAgents = computed(() => store.getters['internalChat/getAgents']);
const addableAgents = computed(() =>
  allAgents.value.filter(a => !members.value.some(m => m.id === a.id))
);
const ADD_SEARCH_MIN = 8;
const filteredAddable = computed(() => {
  const q = addQuery.value.trim().toLowerCase();
  if (!q) return addableAgents.value;
  return addableAgents.value.filter(a =>
    (a.name || '').toLowerCase().includes(q)
  );
});

const trimmedName = computed(() => name.value.trim());
const nameDirty = computed(
  () => trimmedName.value !== (props.channel?.title || '')
);
// Botão Salvar apagado diz por quê.
const saveBlockedReason = computed(() => {
  if (!trimmedName.value) return t('INTERNAL_CHAT.MANAGE.NAME_EMPTY');
  if (!nameDirty.value) return t('INTERNAL_CHAT.MANAGE.NAME_UNCHANGED');
  return '';
});

const rename = async () => {
  if (saveBlockedReason.value || isSaving.value) return;
  isSaving.value = true;
  try {
    await store.dispatch('internalChat/renameChannel', {
      channelId: props.channel.id,
      name: trimmedName.value,
    });
    say(t('INTERNAL_CHAT.MANAGE.RENAMED'));
  } catch {
    say(t('INTERNAL_CHAT.MANAGE.RENAME_ERROR'), true);
  } finally {
    isSaving.value = false;
  }
};

const addMember = async agent => {
  if (busyId.value) return;
  busyId.value = agent.id;
  try {
    await store.dispatch('internalChat/addMember', {
      channelId: props.channel.id,
      userId: agent.id,
    });
    say(t('INTERNAL_CHAT.MANAGE.ADDED', { name: agent.name }));
  } catch {
    say(t('INTERNAL_CHAT.ACTION_ERROR'), true);
  } finally {
    busyId.value = null;
  }
};

const removeMember = async member => {
  confirmRemoveId.value = null;
  busyId.value = member.id;
  try {
    await store.dispatch('internalChat/removeMember', {
      channelId: props.channel.id,
      userId: member.id,
    });
    say(t('INTERNAL_CHAT.MANAGE.REMOVED', { name: member.name }));
  } catch {
    say(t('INTERNAL_CHAT.ACTION_ERROR'), true);
  } finally {
    busyId.value = null;
  }
};

// Sair passa pela mesma confirmação do menu ⋮ (a tela pergunta antes).
const leave = () => {
  emit('close');
  emit('askLeave');
};

// Fechar com nome editado e não salvo: descarta, mas diz.
const close = () => {
  if (props.show && trimmedName.value && nameDirty.value) {
    useAlert(t('INTERNAL_CHAT.MANAGE.NAME_DISCARDED'));
  }
  emit('close');
};

const loadAgents = async () => {
  agentsLoading.value = !allAgents.value.length;
  try {
    await store.dispatch('internalChat/fetchAgents');
  } catch {
    // a lista fica como estava; adicionar continua possível com o que veio
  } finally {
    agentsLoading.value = false;
  }
};

watch(
  () => props.show,
  show => {
    if (show) {
      name.value = props.channel?.title || '';
      addQuery.value = '';
      confirmRemoveId.value = null;
      notice.value = null;
      loadAgents();
      nextTick(() =>
        setTimeout(() => {
          dialogRef.value?.open?.();
          nextTick(() => nameRef.value?.focus());
        }, 10)
      );
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);
</script>

<template>
  <Dialog
    v-if="show && channel"
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.MANAGE.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    show-close-button
    full-height
    width="md"
    @close="close"
  >
    <div class="flex-1 min-h-0 -mx-6 px-6 overflow-y-auto space-y-5">
      <!-- Nome -->
      <div>
        <label
          for="internal-chat-manage-name"
          class="block mb-1.5 text-sm font-medium text-n-slate-11"
        >
          {{ t('INTERNAL_CHAT.MANAGE.NAME') }}
        </label>
        <div class="flex gap-2">
          <input
            id="internal-chat-manage-name"
            ref="nameRef"
            v-model="name"
            type="text"
            maxlength="80"
            class="reset-base flex-1 min-w-0 px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 focus:outline-none focus:border-n-brand"
            @keydown.enter.prevent="rename"
          />
          <span v-tooltip="tip(saveBlockedReason)" class="inline-flex">
            <Button
              type="button"
              color="blue"
              :is-loading="isSaving"
              :disabled="Boolean(saveBlockedReason)"
              @click="rename"
            >
              {{ t('INTERNAL_CHAT.MANAGE.SAVE') }}
            </Button>
          </span>
        </div>
        <p
          v-if="nameDirty"
          class="mt-1.5 mb-0 text-xs"
          :class="trimmedName ? 'text-n-amber-11' : 'text-n-ruby-11'"
        >
          {{
            trimmedName
              ? t('INTERNAL_CHAT.MANAGE.NAME_PENDING')
              : t('INTERNAL_CHAT.MANAGE.NAME_EMPTY')
          }}
        </p>
      </div>

      <!-- Membros -->
      <div>
        <p class="mb-1.5 text-sm font-medium text-n-slate-11">
          {{ t('INTERNAL_CHAT.MANAGE.MEMBERS', { count: members.length }) }}
        </p>
        <div class="space-y-0.5">
          <div
            v-for="member in members"
            :key="member.id"
            class="flex items-center gap-2.5 px-2 min-h-10 py-1.5 rounded-lg"
            :class="
              confirmRemoveId === member.id
                ? 'bg-n-ruby-3'
                : 'hover:bg-n-alpha-1'
            "
          >
            <Avatar
              :src="member.avatar_url"
              :name="member.name"
              :size="26"
              rounded-full
            />
            <template v-if="confirmRemoveId === member.id">
              <span class="flex-1 min-w-0 text-xs leading-snug text-n-ruby-11">
                {{ t('INTERNAL_CHAT.MANAGE.REMOVE_Q', { name: member.name }) }}
              </span>
              <button
                type="button"
                class="px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                @click="confirmRemoveId = null"
              >
                {{ t('INTERNAL_CHAT.CANCEL') }}
              </button>
              <button
                v-focus-on-mount
                type="button"
                class="px-2 py-1 text-xs font-semibold text-white rounded-md bg-n-ruby-9 hover:bg-n-ruby-10"
                @click="removeMember(member)"
              >
                {{ t('INTERNAL_CHAT.MANAGE.REMOVE') }}
              </button>
            </template>
            <template v-else>
              <span
                class="flex-1 min-w-0 text-sm truncate text-n-slate-12"
                :title="member.name"
              >
                {{ member.name }}
              </span>
              <span
                v-if="isMe(member)"
                class="text-[11px] px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ t('INTERNAL_CHAT.INFO.YOU') }}
              </span>
              <span
                v-else-if="busyId === member.id"
                class="i-lucide-loader-circle animate-spin text-n-slate-10"
              />
              <button
                v-else
                v-tooltip="
                  tip(
                    t('INTERNAL_CHAT.MANAGE.REMOVE_NAME', { name: member.name })
                  )
                "
                type="button"
                class="inline-flex items-center justify-center rounded-full size-7 text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                :aria-label="
                  t('INTERNAL_CHAT.MANAGE.REMOVE_NAME', { name: member.name })
                "
                @click="confirmRemoveId = member.id"
              >
                <span class="flex-shrink-0 text-base i-lucide-user-minus" />
              </button>
            </template>
          </div>
        </div>
      </div>

      <!-- Adicionar -->
      <div>
        <p class="mb-1.5 text-sm font-medium text-n-slate-11">
          {{ t('INTERNAL_CHAT.MANAGE.ADD') }}
        </p>
        <div
          v-if="addableAgents.length > ADD_SEARCH_MIN || addQuery"
          class="relative mb-1.5"
        >
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="addQuery"
            type="text"
            :placeholder="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
            :aria-label="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
            class="reset-base w-full h-9 pl-9 pr-3 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:border-n-brand"
          />
        </div>
        <p
          v-if="agentsLoading"
          class="flex items-center gap-2 px-2 py-3 mb-0 text-xs text-n-slate-11"
        >
          <span class="i-lucide-loader-circle animate-spin" />
          {{ t('INTERNAL_CHAT.LOADING') }}
        </p>
        <p
          v-else-if="!addableAgents.length"
          class="px-2 py-3 mb-0 text-xs text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.MANAGE.ALL_IN') }}
        </p>
        <p
          v-else-if="!filteredAddable.length"
          class="px-2 py-3 mb-0 text-xs text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.LIST.NO_PEOPLE_MATCH') }}
        </p>
        <div v-else class="space-y-0.5">
          <button
            v-for="agent in filteredAddable"
            :key="agent.id"
            v-tooltip="
              tip(t('INTERNAL_CHAT.MANAGE.ADD_NAME', { name: agent.name }))
            "
            type="button"
            class="flex items-center gap-2.5 w-full px-2 py-1.5 rounded-lg text-sm text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-60"
            :disabled="Boolean(busyId)"
            @click="addMember(agent)"
          >
            <Avatar
              :src="agent.avatar_url"
              :name="agent.name"
              :size="24"
              rounded-full
            />
            <span class="flex-1 text-left truncate">{{ agent.name }}</span>
            <span
              v-if="busyId === agent.id"
              class="i-lucide-loader-circle animate-spin text-n-slate-10"
            />
            <span
              v-else
              class="flex-shrink-0 text-base i-lucide-user-plus text-n-slate-10"
            />
          </button>
        </div>
      </div>
    </div>

    <template #footer>
      <p
        v-if="notice"
        role="status"
        class="flex items-center gap-1.5 px-3 py-2 -mb-3 text-xs rounded-lg shrink-0"
        :class="
          notice.error
            ? 'bg-n-ruby-3 text-n-ruby-11'
            : 'bg-n-teal-3 text-n-teal-11'
        "
      >
        <span
          class="flex-shrink-0 text-sm"
          :class="notice.error ? 'i-lucide-circle-alert' : 'i-lucide-check'"
        />
        {{ notice.text }}
      </p>
      <div
        class="flex items-center justify-between w-full pt-4 border-t shrink-0 border-n-weak"
      >
        <Button type="button" variant="ghost" color="ruby" @click="leave">
          {{ t('INTERNAL_CHAT.MANAGE.LEAVE') }}
        </Button>
        <Button
          type="button"
          variant="faded"
          color="slate"
          @click="dialogRef?.close()"
        >
          {{ t('INTERNAL_CHAT.MANAGE.CLOSE') }}
        </Button>
      </div>
    </template>
  </Dialog>
</template>
