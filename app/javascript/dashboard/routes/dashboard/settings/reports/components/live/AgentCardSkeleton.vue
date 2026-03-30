<script setup>
import { ref, onMounted, onUnmounted } from 'vue';

// Tema atual para data-theme (controle de shimmer/estilo)
const theme = ref(
  document.body?.classList?.contains('dark') ? 'dark' : 'light'
);
let observer = null;

function updateTheme() {
  theme.value = document.body?.classList?.contains('dark') ? 'dark' : 'light';
}

onMounted(() => {
  updateTheme();
  observer = new MutationObserver(updateTheme);
  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
});

onUnmounted(() => {
  observer?.disconnect();
});
</script>

<template>
  <div
    :data-theme="theme"
    class="agent-card-skeleton flex flex-col h-[400px] bg-n-solid-2 rounded-xl shadow outline-1 outline outline-n-container overflow-hidden"
  >
    <!-- Header: avatar + nome + status -->
    <div
      class="flex items-center gap-3 p-4 border-b border-n-weak bg-n-alpha-2 flex-shrink-0"
    >
      <div class="skeleton-box size-10 rounded-full flex-shrink-0" />
      <div class="flex-1 min-w-0 space-y-2">
        <div class="skeleton-box h-4 w-3/4 max-w-[140px] rounded-md" />
        <div class="skeleton-box h-3 w-1/2 max-w-[80px] rounded-full" />
      </div>
    </div>
    <!-- Body: itens de conversa -->
    <div class="flex-1 min-h-0 overflow-hidden p-4 space-y-4">
      <div v-for="n in 4" :key="n" class="flex items-center gap-3">
        <div class="skeleton-box size-8 rounded-full flex-shrink-0" />
        <div class="flex-1 min-w-0 space-y-1.5">
          <div class="skeleton-box h-3 w-2/3 rounded-md" />
          <div class="skeleton-box h-3 w-1/2 rounded-md" />
        </div>
      </div>
    </div>
    <!-- Footer: total de chamadas -->
    <div
      class="p-4 border-t border-n-weak bg-n-alpha-2 flex-shrink-0 flex items-center justify-between gap-2"
    >
      <div class="skeleton-box h-4 w-28 rounded-md" />
      <div class="skeleton-box h-7 min-w-[1.75rem] w-10 rounded-lg" />
    </div>
  </div>
</template>

<style scoped>
.skeleton-box {
  @apply bg-n-slate-3;
  position: relative;
  overflow: hidden;
}

.skeleton-box::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    90deg,
    transparent 0%,
    rgba(255, 255, 255, 0.12) 50%,
    transparent 100%
  );
  background-size: 200% 100%;
  animation: shimmer 1.6s ease-in-out infinite;
}

:global(.dark) .skeleton-box::after {
  background: linear-gradient(
    90deg,
    transparent 0%,
    rgba(255, 255, 255, 0.06) 50%,
    transparent 100%
  );
}

@keyframes shimmer {
  0% {
    background-position: 200% 0;
  }
  100% {
    background-position: -200% 0;
  }
}
</style>
