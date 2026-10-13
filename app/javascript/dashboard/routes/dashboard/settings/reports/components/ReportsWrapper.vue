<script setup>
import { REPORTS_WALLPAPER } from 'dashboard/components-next/reports/ui/styles';
</script>

<template>
  <div
    class="w-full px-6 overflow-auto bg-n-surface-1 bg-repeat"
    :class="REPORTS_WALLPAPER"
  >
    <div class="flex flex-col gap-4 max-w-[90rem] mx-auto pb-12">
      <router-view />
    </div>
  </div>
</template>
