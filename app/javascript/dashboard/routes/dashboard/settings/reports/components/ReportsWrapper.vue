<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <!-- O painel de Relatorios (meta.wide) usa a largura toda; os relatorios detalhados seguem estreitos. -->
    <div
      class="mx-auto pb-12"
      :class="$route.meta.wide ? 'max-w-[90rem]' : 'max-w-5xl'"
    >
      <router-view />
    </div>
  </div>
</template>
