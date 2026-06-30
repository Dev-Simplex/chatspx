<script setup>
// Fundo com profundidade (blobs desfocados estilo "aurora") pras telas dos Agentes
// IA — é o que o glassmorphism dos cards embaça por baixo, senão o vidro fica sem
// efeito sobre fundo chapado. Decorativo (aria-hidden, sem interação).
// IMPORTANTE: o container pai precisa de `isolate` (stacking context), senão este
// backdrop com -z-10 afunda atrás do bg do pai e some.
defineOptions({ name: 'AiBackdrop' });
</script>

<template>
  <div
    aria-hidden="true"
    class="overflow-hidden absolute inset-0 -z-10 pointer-events-none"
  >
    <div
      class="absolute rounded-full -top-32 -left-24 size-96 bg-n-brand/20 blur-3xl"
    />
    <div
      class="absolute -right-24 top-1/4 rounded-full size-[30rem] bg-[#8b5cf6]/[0.16] blur-3xl"
    />
    <div
      class="absolute -bottom-32 left-1/3 rounded-full size-96 bg-[#0ea5e9]/[0.16] blur-3xl"
    />
  </div>
</template>
