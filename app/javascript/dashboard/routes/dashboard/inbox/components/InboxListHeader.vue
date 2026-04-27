<script>
export default {
  name: 'InboxListHeader',
};
</script>

<template>
  <div
    class="flex items-center justify-between w-full gap-1 h-[3.25rem] ltr:pl-4 rtl:pr-4 ltr:pr-3 rtl:pl-3"
  >
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <h1 class="text-heading-2 truncate text-n-slate-12 min-w-0">
        {{ $t('INBOX.LIST.TITLE') }}
      </h1>
    </div>
    <!-- Dropdowns "Exibir" e ações em massa (Marcar todas / Excluir todas)
         removidos: comportamento WhatsApp-like — notificação some
         automaticamente quando user abre/lê a conversa. -->
    <div />
  </div>
</template>
