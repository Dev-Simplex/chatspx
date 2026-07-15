<script setup>
import { ref, watch, onMounted, nextTick } from 'vue';
import MessageBubble from './MessageBubble.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  currentUserId: { type: [Number, String], default: null },
});

defineEmits(['react', 'edit', 'delete', 'reply', 'retry']);

const scroller = ref(null);

// Rola até a mensagem citada e a destaca por um instante (clique no reply).
const scrollToMessage = id => {
  const el = scroller.value?.querySelector(`[data-msg-id="${id}"]`);
  if (!el) return;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.classList.add('ring-2', 'ring-n-brand/60', 'rounded-2xl');
  setTimeout(
    () => el.classList.remove('ring-2', 'ring-n-brand/60', 'rounded-2xl'),
    1400
  );
};

const scrollToBottom = (smooth = false) => {
  const el = scroller.value;
  if (!el) return;
  el.scrollTo({ top: el.scrollHeight, behavior: smooth ? 'smooth' : 'auto' });
};

// Ao abrir/trocar de conversa (remontagem via :key) já mostra o fim da thread.
onMounted(() => nextTick(() => scrollToBottom(false)));

// Mensagem nova na mesma conversa → desce suave acompanhando o balão.
watch(
  () => props.items.length,
  (next, prev) => {
    if (next > prev) nextTick(() => scrollToBottom(true));
  }
);
</script>

<template>
  <div
    ref="scroller"
    class="flex-1 min-h-0 px-4 py-5 overflow-y-auto md:px-8 bg-n-background thread-fade"
  >
    <TransitionGroup tag="div" name="msg" class="space-y-3">
      <div v-for="item in items" :key="item.id">
        <!-- Day divider -->
        <div v-if="item.type === 'day'" class="flex justify-center py-1">
          <span
            class="px-3 py-1 text-[11px] font-medium rounded-full text-n-slate-11 bg-n-alpha-1"
          >
            {{ item.label }}
          </span>
        </div>

        <!-- Unread divider -->
        <div
          v-else-if="item.type === 'unread'"
          class="flex items-center gap-3 py-1"
        >
          <span class="flex-1 h-px bg-n-brand/30" />
          <span class="text-[11px] font-medium text-n-brand">
            {{ item.label }}
          </span>
          <span class="flex-1 h-px bg-n-brand/30" />
        </div>

        <!-- Message -->
        <MessageBubble
          v-else
          :message="item"
          :current-user-id="currentUserId"
          @react="$emit('react', $event)"
          @edit="$emit('edit', $event)"
          @delete="$emit('delete', $event)"
          @reply="$emit('reply', $event)"
          @retry="$emit('retry', $event)"
          @scroll-to="scrollToMessage"
        />
      </div>
    </TransitionGroup>
  </div>
</template>

<style scoped>
/* Fade suave da thread inteira ao abrir/trocar de conversa (roda na montagem). */
.thread-fade {
  animation: threadFade 0.22s ease-out;
}
@keyframes threadFade {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

/* Balão novo entra deslizando de baixo (não dispara no carregamento inicial). */
.msg-enter-active {
  transition:
    opacity 0.25s ease,
    transform 0.25s ease;
}
.msg-enter-from {
  opacity: 0;
  transform: translateY(10px) scale(0.98);
}
/* Reacomodação suave dos itens restantes (ex.: filtro de busca). */
.msg-move {
  transition: transform 0.25s ease;
}
</style>
