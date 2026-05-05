<script setup>
// Copilot Loader 2026 — Sparkles + Shimmer
</script>

<template>
  <div class="flex justify-start w-full">
    <div class="flex items-start gap-2 w-full">
      <div class="relative flex items-center justify-center size-8 shrink-0">
        <span
          class="i-lucide-sparkles size-4 text-n-brand absolute top-[4px] left-[4px] ai-sparkle ai-sparkle-delay-1"
        />
        <span
          class="i-lucide-sparkle size-3 text-n-brand absolute top-[14px] left-[18px] ai-sparkle ai-sparkle-delay-2"
        />
        <span
          class="i-lucide-sparkle size-2.5 text-n-brand/70 absolute top-[22px] left-[8px] ai-sparkle ai-sparkle-delay-3"
        />
      </div>
      <div class="flex flex-col gap-2 flex-1 pt-1">
        <span class="text-xs text-n-slate-11 font-medium">
          {{ $t('CAPTAIN.COPILOT.LOADER') }}
        </span>
        <div class="space-y-1.5 w-full">
          <div class="h-2 rounded-full ai-shimmer w-3/4" />
          <div class="h-2 rounded-full ai-shimmer w-1/2" />
        </div>
      </div>
    </div>
  </div>
</template>
