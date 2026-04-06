<script>
// Copilot Loader Component
</script>

<template>
  <div class="flex justify-start">
    <div class="flex items-center space-x-2">
      <span class="text-xs text-n-slate-10 italic">
        {{ $t('CAPTAIN.COPILOT.LOADER') }}
      </span>
      <div class="flex space-x-1">
        <div
          class="w-1.5 h-1.5 rounded-full bg-n-brand animate-bounce [animation-delay:-0.3s]"
        />
        <div
          class="w-1.5 h-1.5 rounded-full bg-n-brand animate-bounce [animation-delay:-0.15s]"
        />
        <div class="w-1.5 h-1.5 rounded-full bg-n-brand animate-bounce" />
      </div>
    </div>
  </div>
</template>
