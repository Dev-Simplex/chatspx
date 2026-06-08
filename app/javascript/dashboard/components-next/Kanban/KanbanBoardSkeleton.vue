<script setup>
// KANBAN-P3-07: skeleton de loading do board. 4 colunas, 5 cards cada.
</script>

<template>
  <div
    role="status"
    aria-live="polite"
    class="flex flex-1 min-h-0 gap-3 overflow-x-auto overflow-y-hidden px-4 py-4"
  >
    <div
      v-for="col in 4"
      :key="`skel-col-${col}`"
      class="flex w-72 flex-shrink-0 flex-col gap-2 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3"
    >
      <div class="flex items-center justify-between gap-2">
        <span
          class="h-4 w-24 rounded bg-slate-200 dark:bg-slate-700 animate-pulse"
        />
        <span
          class="h-3 w-8 rounded bg-slate-200 dark:bg-slate-700 animate-pulse"
        />
      </div>
      <div
        v-for="row in 5"
        :key="`skel-card-${col}-${row}`"
        class="flex flex-col gap-1.5 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-3 py-2.5"
      >
        <div class="flex items-center gap-2">
          <span
            class="size-8 rounded-full bg-slate-200 dark:bg-slate-700 animate-pulse"
          />
          <span
            class="h-3 w-32 rounded bg-slate-200 dark:bg-slate-700 animate-pulse"
          />
        </div>
        <span
          class="h-2.5 w-full rounded bg-slate-200 dark:bg-slate-700 animate-pulse"
        />
        <div class="flex items-center gap-1.5">
          <span
            class="h-2.5 w-12 rounded-full bg-slate-200 dark:bg-slate-700 animate-pulse"
          />
          <span
            class="h-2.5 w-10 rounded-full bg-slate-200 dark:bg-slate-700 animate-pulse"
          />
        </div>
      </div>
    </div>
  </div>
</template>
