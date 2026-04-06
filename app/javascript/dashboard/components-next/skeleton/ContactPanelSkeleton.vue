<template>
  <div class="flex flex-col items-center gap-4 p-6">
    <!-- Large avatar -->
    <div class="bg-n-slate-3 animate-pulse rounded-full size-16" />
    <!-- Name -->
    <div class="bg-n-slate-3 animate-pulse rounded h-4 w-32" />
    <!-- Status / subtitle -->
    <div class="bg-n-slate-3 animate-pulse rounded h-3 w-24" />

    <!-- Section lines -->
    <div class="w-full space-y-4 mt-4">
      <div v-for="n in 3" :key="n" class="space-y-2">
        <div class="bg-n-slate-3 animate-pulse rounded h-3 w-20" />
        <div class="bg-n-slate-3 animate-pulse rounded h-8 w-full" />
      </div>
    </div>
  </div>
</template>
