<script setup>
// "Dados da mensagem" (grupo): quem já leu e quem ainda não leu, pelo
// last_read_at de cada participante.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import InternalChatAPI from 'dashboard/api/internalChat';
import { useEscClose } from './useEscClose';
import { whenText } from './lastSeen';

const props = defineProps({
  channelId: { type: [Number, String], required: true },
  // Item da thread (id, content, attachments, time…).
  message: { type: Object, required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();

useEscClose(
  () => true,
  () => emit('close')
);

const state = ref('loading'); // loading | ready | error
const read = ref([]);
const unread = ref([]);
const query = ref('');
const SEARCH_MIN = 8;

const load = async () => {
  state.value = 'loading';
  try {
    const { data } = await InternalChatAPI.getReceipts(
      props.channelId,
      props.message.id
    );
    read.value = data.read || [];
    unread.value = data.unread || [];
    state.value = 'ready';
  } catch {
    state.value = 'error';
  }
};
onMounted(load);

const filter = list => {
  const q = query.value.trim().toLowerCase();
  return q ? list.filter(p => (p.name || '').toLowerCase().includes(q)) : list;
};
const visibleRead = computed(() => filter(read.value));
const visibleUnread = computed(() => filter(unread.value));
const showSearch = computed(
  () => read.value.length + unread.value.length > SEARCH_MIN
);

const readAt = ts => whenText(t, ts);

const preview = computed(() => {
  const m = props.message;
  if (m.content) return m.content;
  return `📎 ${(m.attachments || []).map(a => a.filename).join(', ')}`;
});
</script>

<template>
  <!-- No body: cobre a tela toda (dentro da coluna da conversa o fundo
       escuro parava na lista). -->
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="emit('close')"
    >
      <div
        role="dialog"
        aria-modal="true"
        :aria-label="t('INTERNAL_CHAT.MESSAGE_INFO.TITLE')"
        class="flex flex-col w-full max-w-md max-h-[min(36rem,calc(100%-2rem))] border shadow-xl rounded-3xl bg-n-solid-1 border-n-weak"
      >
        <header class="flex items-center gap-2 px-5 pt-4 pb-2">
          <span class="flex-shrink-0 i-lucide-info size-5 text-n-teal-11" />
          <h3 class="flex-1 mb-0 text-base font-semibold text-n-slate-12">
            {{ t('INTERNAL_CHAT.MESSAGE_INFO.TITLE') }}
          </h3>
          <button
            v-tooltip="t('INTERNAL_CHAT.CLOSE')"
            type="button"
            class="inline-flex items-center justify-center -me-2 rounded-full size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
            :aria-label="t('INTERNAL_CHAT.CLOSE')"
            @click="emit('close')"
          >
            <span class="flex-shrink-0 size-5 i-lucide-x" />
          </button>
        </header>

        <div
          class="px-3 py-2 mx-5 text-xs border-l-[3px] rounded-lg border-n-teal-9 bg-n-alpha-1 text-n-slate-11"
        >
          <span class="block truncate text-n-slate-12">{{ preview }}</span>
          <span class="block mt-0.5">
            {{
              t('INTERNAL_CHAT.MESSAGE_INFO.SENT_AT', { time: message.time })
            }}
          </span>
        </div>

        <div v-if="showSearch && state === 'ready'" class="px-5 pt-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-3 top-1/2 text-n-slate-10"
            />
            <input
              v-model="query"
              type="text"
              :placeholder="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
              :aria-label="t('INTERNAL_CHAT.LIST.PEOPLE_SEARCH')"
              class="reset-base w-full h-9 pl-9 pr-3 text-sm border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
            />
          </div>
        </div>

        <div class="flex-1 min-h-0 px-5 pt-3 pb-4 overflow-y-auto">
          <p
            v-if="state === 'loading'"
            class="flex items-center justify-center gap-2 py-8 mb-0 text-sm text-n-slate-11"
          >
            <span class="i-lucide-loader-circle animate-spin" />
            {{ t('INTERNAL_CHAT.LOADING') }}
          </p>
          <div
            v-else-if="state === 'error'"
            class="flex flex-col items-center gap-3 py-8 text-center"
          >
            <span class="text-2xl i-lucide-wifi-off text-n-ruby-11" />
            <p class="mb-0 text-sm text-n-slate-12">
              {{ t('INTERNAL_CHAT.MESSAGE_INFO.ERROR') }}
            </p>
            <button
              type="button"
              class="px-4 py-1.5 text-xs font-semibold rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
              @click="load"
            >
              {{ t('INTERNAL_CHAT.RETRY') }}
            </button>
          </div>
          <template v-else>
            <section
              v-for="section in [
                {
                  key: 'read',
                  title: t('INTERNAL_CHAT.MESSAGE_INFO.READ_BY', {
                    count: read.length,
                  }),
                  icon: 'i-lucide-check-check text-n-teal-11',
                  items: visibleRead,
                  empty: t('INTERNAL_CHAT.MESSAGE_INFO.NOBODY_READ'),
                },
                {
                  key: 'unread',
                  title: t('INTERNAL_CHAT.MESSAGE_INFO.NOT_READ', {
                    count: unread.length,
                  }),
                  icon: 'i-lucide-check text-n-slate-10',
                  items: visibleUnread,
                  empty: t('INTERNAL_CHAT.MESSAGE_INFO.EVERYONE_READ'),
                },
              ]"
              :key="section.key"
              class="mb-4 last:mb-0"
            >
              <p
                class="flex items-center gap-1.5 mb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
              >
                <span class="size-4" :class="section.icon" />
                {{ section.title }}
              </p>
              <p
                v-if="!section.items.length"
                class="px-3 py-3 mb-0 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
              >
                {{
                  query.trim()
                    ? t('INTERNAL_CHAT.LIST.NO_PEOPLE_MATCH')
                    : section.empty
                }}
              </p>
              <div v-else class="overflow-hidden rounded-2xl bg-n-alpha-1">
                <div
                  v-for="person in section.items"
                  :key="person.id"
                  class="flex items-center gap-3 px-3 py-2 border-b last:border-b-0 border-n-weak"
                >
                  <Avatar
                    :name="person.name || ''"
                    :src="person.avatar_url || ''"
                    :size="32"
                    rounded-full
                  />
                  <span class="flex-1 min-w-0 text-sm truncate text-n-slate-12">
                    {{ person.name }}
                  </span>
                  <span
                    v-if="section.key === 'read'"
                    v-tooltip="t('INTERNAL_CHAT.MESSAGE_INFO.READ_AT_HINT')"
                    class="flex-shrink-0 text-xs tabular-nums text-n-slate-11"
                  >
                    {{ readAt(person.last_read_at) }}
                  </span>
                </div>
              </div>
            </section>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>
