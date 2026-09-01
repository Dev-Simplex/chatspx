<script setup>
/**
 * Chips de reação — ÚNICO lugar do painel que desenha um chip de reação.
 *
 * Atende duas origens com o mesmo desenho:
 *   a) reação do painel (`reactions`, mapa `{userId: [emoji]}`): interativa, com seletor
 *      de emoji e toggle via API;
 *   b) reação vinda do WhatsApp (`chips`, já agregados pelo `whatsappReactionHelper`):
 *      `readonly`, porque não existe API para reagir de volta no WhatsApp — o chip aqui
 *      é leitura do que aconteceu no celular de quem reagiu.
 *
 * `chips` tem precedência sobre `reactions`; `readonly` desliga seletor e toggle.
 */
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import MessageApi from 'dashboard/api/inbox/message';

const props = defineProps({
  messageId: { type: [Number, String], default: null },
  conversationId: { type: [Number, String], default: null },
  reactions: { type: Object, default: () => ({}) },
  currentUserId: { type: [Number, String], default: null },
  /**
   * Chips já agregados por quem chamou: `[{ emoji, count, title }]`. Quando presente,
   * o componente não agrega nada — só desenha.
   */
  chips: { type: Array, default: null },
  readonly: { type: Boolean, default: false },
  mode: {
    type: String,
    default: 'all',
    validator: v => ['all', 'picker', 'chips'].includes(v),
  },
});

const EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];
const showPicker = ref(false);
const store = useStore();

const aggregated = computed(() => {
  const out = {};
  Object.entries(props.reactions || {}).forEach(([userId, list]) => {
    (list || []).forEach(emoji => {
      if (!out[emoji]) out[emoji] = { count: 0, users: [] };
      out[emoji].count += 1;
      out[emoji].users.push(Number(userId));
    });
  });
  return out;
});

const userHasEmoji = emoji =>
  aggregated.value[emoji]?.users.includes(Number(props.currentUserId));

/**
 * Lista única de chips desenhados, venha ela pronta (WhatsApp) ou da agregação local.
 * @returns {Array<{emoji: String, count: Number, title: String, mine: Boolean}>}
 */
const chipList = computed(() => {
  if (props.chips) {
    return props.chips.map(chip => ({ mine: false, title: '', ...chip }));
  }

  return Object.entries(aggregated.value).map(([emoji, info]) => ({
    emoji,
    count: info.count,
    title: '',
    mine: userHasEmoji(emoji),
  }));
});

const hasReactions = computed(() => chipList.value.length > 0);

const toggle = async emoji => {
  showPicker.value = false;
  try {
    const { data } = await MessageApi.toggleReaction(
      props.conversationId,
      props.messageId,
      emoji
    );
    const conversationId = Number(props.conversationId);
    const messageId = Number(props.messageId);
    const conversation = store.getters.getConversationById(conversationId);
    const existing = (conversation?.messages || []).find(
      m => Number(m.id) === messageId
    );
    if (existing) {
      store.dispatch('updateMessage', {
        ...existing,
        additional_attributes: {
          ...(existing.additional_attributes || {}),
          reactions: data.reactions,
        },
      });
    }
  } catch {
    // websocket will reconcile
  }
};

const isPickerMode = computed(
  () => !props.readonly && (props.mode === 'picker' || props.mode === 'all')
);
const isChipsMode = computed(
  () => (props.mode === 'chips' || props.mode === 'all') && hasReactions.value
);
const shouldRender = computed(() => isPickerMode.value || isChipsMode.value);
const rootClass = computed(() => {
  // Read-only cola o chip na bolha (padrão WhatsApp); interativo mantém o respiro
  // do seletor.
  if (props.mode === 'chips') {
    return props.readonly
      ? 'flex flex-wrap gap-1 mt-1'
      : 'flex flex-wrap gap-1 mt-2';
  }
  return 'relative inline-block';
});
</script>

<template>
  <!-- eslint-disable-next-line vue/no-root-v-if -->
  <div v-if="shouldRender" :class="rootClass">
    <template v-if="isPickerMode">
      <button
        type="button"
        class="reaction-trigger w-7 h-7 rounded-full bg-n-solid-1/80 backdrop-blur-sm border border-n-weak text-xs flex items-center justify-center hover:bg-n-alpha-3 transition-colors shadow-sm"
        :class="{ 'bg-n-alpha-3': showPicker }"
        :title="$t('CONVERSATION.REACTIONS.PICKER_TOOLTIP')"
        @click.stop="showPicker = !showPicker"
      >
        <span class="text-sm leading-none">+</span>
      </button>

      <div
        v-if="showPicker"
        class="absolute top-0 right-0 -translate-y-full mt-1 z-20 bg-n-solid-2 rounded-full border border-n-weak shadow-lg px-2 py-1 flex gap-1"
        @click.stop
      >
        <button
          v-for="emoji in EMOJIS"
          :key="emoji"
          type="button"
          class="text-lg w-7 h-7 hover:scale-125 transition-transform leading-none"
          @click="toggle(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
    </template>

    <Component
      :is="readonly ? 'span' : 'button'"
      v-for="chip in isChipsMode ? chipList : []"
      :key="chip.emoji"
      v-tooltip.top="chip.title || undefined"
      :type="readonly ? undefined : 'button'"
      :aria-label="chip.title || undefined"
      class="reaction-chip flex items-center gap-1 rounded-full border leading-none"
      :class="[
        readonly
          ? 'reaction-chip--readonly px-1.5 py-0.5 text-[11px] bg-n-solid-1 border-n-weak text-n-slate-11 shadow-sm'
          : 'px-2 py-0.5 text-xs transition-colors cursor-pointer',
        !readonly &&
          (chip.mine
            ? 'bg-n-solid-blue border-n-blue-9 text-n-slate-12'
            : 'bg-n-solid-2 border-n-weak text-n-slate-12 hover:bg-n-alpha-3'),
      ]"
      @click.stop="readonly ? null : toggle(chip.emoji)"
    >
      <span>{{ chip.emoji }}</span>
      <span :class="readonly ? 'tabular-nums' : 'text-[11px]'">
        {{ chip.count }}
      </span>
    </Component>
  </div>
</template>
