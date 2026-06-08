<script setup>
defineProps({
  agent: { type: Object, required: true },
});

defineEmits(['select']);
</script>

<template>
  <button
    class="group flex w-full flex-col rounded-xl border border-n-weak bg-white p-5 text-left transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
    @click="$emit('select', agent)"
  >
    <div class="mb-3 flex items-center gap-3">
      <div
        class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary-500 to-blue-500 text-base font-semibold text-white"
      >
        {{ (agent.name || '?')[0].toUpperCase() }}
      </div>
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-semibold text-n-slate-12">
          {{ agent.name }}
        </p>
        <p v-if="agent.config?.model" class="text-xs text-n-slate-10">
          {{ agent.config.model }}
        </p>
      </div>
    </div>
    <p
      v-if="agent.description"
      class="mb-3 line-clamp-2 text-sm text-n-slate-10"
    >
      {{ agent.description }}
    </p>
    <div
      class="mt-auto flex items-center justify-between border-t border-n-weak pt-3 text-xs text-n-slate-10"
    >
      <span class="flex items-center gap-1">
        <i class="i-lucide-inbox size-3" />
        {{ agent.account_inbox_ids?.length || 0 }}
        {{ $t('AGENTS_DASHBOARD.INBOXES_LABEL') }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span
          class="size-1.5 rounded-full"
          :class="agent.active ? 'bg-green-500' : 'bg-n-slate-8'"
        />
        {{
          agent.active ? $t('AGENTS_PAGE.ACTIVE') : $t('AGENTS_PAGE.INACTIVE')
        }}
      </span>
    </div>
  </button>
</template>
