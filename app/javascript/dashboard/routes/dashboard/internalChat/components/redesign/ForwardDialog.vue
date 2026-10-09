<script setup>
// "Encaminhar": escolhe 1+ conversas (grupos, times, DMs) ou pessoas sem
// conversa ainda e manda a mesma mensagem com o selo "Encaminhada".
import { ref, computed, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useEscClose } from './useEscClose';

const props = defineProps({
  // Item da thread que será encaminhado (content, attachments, senderName…).
  message: { type: Object, required: true },
  // Conversas já mapeadas pela página (só as que eu participo contam).
  conversations: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
  // Envio em andamento / falhou (a página faz a chamada).
  sending: { type: Boolean, default: false },
  failed: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'forward']);
const { t } = useI18n();

const query = ref('');
const searchRef = ref(null);
// Chaves "c-<id>" (conversa) e "u-<id>" (pessoa sem conversa).
const picked = ref([]);

useEscClose(
  () => true,
  () => emit('close')
);
onMounted(() => nextTick(() => searchRef.value?.focus()));

const matches = name =>
  (name || '').toLowerCase().includes(query.value.trim().toLowerCase());

const kindOf = c => {
  if (c.isTeam) return t('INTERNAL_CHAT.LIST.TEAM_BADGE');
  return c.isGroup ? t('INTERNAL_CHAT.LIST.GROUP_BADGE') : '';
};
const conversationTargets = computed(() =>
  props.conversations
    .filter(c => !c.readOnly && matches(c.name))
    .map(c => ({
      key: `c-${c.id}`,
      name: c.name,
      avatarSrc: c.avatarSrc,
      iconName: c.iconName,
      kind: kindOf(c),
    }))
);
// Pessoas com quem ainda não há conversa: a DM nasce no envio.
const peopleTargets = computed(() => {
  const withDm = new Set(
    props.conversations
      .filter(c => c.channelType === 'direct')
      .flatMap(c => (c.members || []).map(m => m.id))
  );
  return props.agents
    .filter(
      a =>
        Number(a.id) !== Number(props.currentUserId) &&
        !withDm.has(a.id) &&
        matches(a.name)
    )
    .map(a => ({
      key: `u-${a.id}`,
      name: a.name,
      avatarSrc: a.avatar_url || a.thumbnail || '',
      iconName: null,
      kind: '',
    }));
});
const noMatch = computed(
  () => !conversationTargets.value.length && !peopleTargets.value.length
);

const isPicked = key => picked.value.includes(key);
const toggle = key => {
  if (props.sending) return;
  picked.value = isPicked(key)
    ? picked.value.filter(k => k !== key)
    : [...picked.value, key];
};

// Diz o que falta em vez de só apagar o botão.
const blockedReason = computed(() => {
  if (props.sending) return t('INTERNAL_CHAT.FORWARD.SENDING');
  if (!picked.value.length) return t('INTERNAL_CHAT.FORWARD.PICK_FIRST');
  return '';
});

const preview = computed(() => {
  const m = props.message;
  if (m.content) return m.content;
  if (m.sharedConversation)
    return t('INTERNAL_CHAT.FORWARD.PREVIEW_CONVERSATION', {
      id: m.sharedConversation.display_id,
    });
  return `📎 ${(m.attachments || []).map(a => a.filename).join(', ')}`;
});

const submit = () => {
  if (blockedReason.value) return;
  const ids = prefix =>
    picked.value.filter(k => k.startsWith(prefix)).map(k => Number(k.slice(2)));
  emit('forward', { channelIds: ids('c-'), userIds: ids('u-') });
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    @click.self="emit('close')"
  >
    <div
      role="dialog"
      aria-modal="true"
      :aria-label="t('INTERNAL_CHAT.FORWARD.TITLE')"
      class="flex flex-col w-full max-w-md max-h-[min(36rem,calc(100%-2rem))] border shadow-xl rounded-3xl bg-n-solid-1 border-n-weak"
    >
      <header class="flex items-center gap-2 px-5 pt-4 pb-2">
        <span class="i-lucide-forward size-5 text-n-teal-11" />
        <h3 class="flex-1 mb-0 text-base font-semibold text-n-slate-12">
          {{ t('INTERNAL_CHAT.FORWARD.TITLE') }}
        </h3>
        <button
          v-tooltip="t('INTERNAL_CHAT.CLOSE')"
          type="button"
          class="inline-flex items-center justify-center -me-2 rounded-full size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
          :aria-label="t('INTERNAL_CHAT.CLOSE')"
          @click="emit('close')"
        >
          <span class="text-lg i-lucide-x" />
        </button>
      </header>

      <!-- O que vai ser encaminhado -->
      <div
        class="px-3 py-2 mx-5 text-xs border-l-[3px] rounded-lg border-n-teal-9 bg-n-alpha-1 text-n-slate-11"
      >
        <span class="block font-semibold text-n-slate-12">
          {{ message.senderName }}
        </span>
        <span class="block truncate">{{ preview }}</span>
      </div>

      <div class="px-5 pt-3 pb-2">
        <div class="relative">
          <span
            class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
          />
          <input
            ref="searchRef"
            v-model="query"
            type="text"
            :placeholder="t('INTERNAL_CHAT.FORWARD.SEARCH')"
            :aria-label="t('INTERNAL_CHAT.FORWARD.SEARCH')"
            class="reset-base w-full h-9 pl-9 pr-3 text-sm border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
          />
        </div>
      </div>

      <div class="flex-1 min-h-0 px-3 pb-2 overflow-y-auto">
        <p
          v-if="noMatch"
          class="px-3 py-6 mb-0 text-xs text-center text-n-slate-10"
        >
          {{ t('INTERNAL_CHAT.FORWARD.NO_MATCH') }}
        </p>
        <template
          v-for="section in [
            {
              key: 'conv',
              title: t('INTERNAL_CHAT.FORWARD.CONVERSATIONS'),
              items: conversationTargets,
            },
            {
              key: 'people',
              title: t('INTERNAL_CHAT.FORWARD.PEOPLE'),
              items: peopleTargets,
            },
          ]"
          :key="section.key"
        >
          <template v-if="section.items.length">
            <p
              class="px-2 pt-2 pb-1 mb-0 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
            >
              {{ section.title }}
            </p>
            <label
              v-for="item in section.items"
              :key="item.key"
              class="flex items-center gap-3 px-2 py-1.5 rounded-xl cursor-pointer hover:bg-n-alpha-1 focus-within:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                class="accent-n-teal-10 size-4"
                :checked="isPicked(item.key)"
                :disabled="sending"
                @change="toggle(item.key)"
              />
              <Avatar
                :name="item.name || ''"
                :src="item.avatarSrc || ''"
                :icon-name="item.iconName"
                :size="32"
                rounded-full
              />
              <span class="flex-1 min-w-0 text-sm truncate text-n-slate-12">
                {{ item.name }}
              </span>
              <span
                v-if="item.kind"
                class="flex-shrink-0 px-1.5 py-px text-[10px] font-semibold rounded-md uppercase tracking-wide bg-n-alpha-2 text-n-slate-11"
              >
                {{ item.kind }}
              </span>
            </label>
          </template>
        </template>
      </div>

      <footer class="px-5 pt-3 pb-4 border-t border-n-weak">
        <p
          v-if="failed"
          class="flex items-center gap-1.5 mb-2 text-xs text-n-ruby-11"
          role="alert"
        >
          <span class="flex-shrink-0 i-lucide-circle-alert size-4" />
          {{ t('INTERNAL_CHAT.FORWARD.ERROR') }}
        </p>
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs text-n-slate-11">
            {{
              picked.length
                ? t('INTERNAL_CHAT.FORWARD.SELECTED', { count: picked.length })
                : blockedReason
            }}
          </span>
          <span class="flex gap-2">
            <button
              type="button"
              class="px-3 py-1.5 text-sm font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
              @click="emit('close')"
            >
              {{ t('INTERNAL_CHAT.CANCEL') }}
            </button>
            <span v-tooltip="blockedReason" class="inline-flex">
              <button
                type="button"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-semibold text-white rounded-lg bg-n-teal-10 dark:bg-n-teal-9 hover:bg-n-teal-11 disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-teal-9"
                :disabled="Boolean(blockedReason)"
                @click="submit"
              >
                <span
                  v-if="sending"
                  class="i-lucide-loader-circle animate-spin size-4"
                />
                <span v-else class="i-lucide-forward size-4" />
                {{
                  failed
                    ? t('INTERNAL_CHAT.RETRY')
                    : t('INTERNAL_CHAT.FORWARD.CONFIRM')
                }}
              </button>
            </span>
          </span>
        </div>
      </footer>
    </div>
  </div>
</template>
