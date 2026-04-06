<script setup>
defineProps({
  count: {
    type: Number,
    default: 5,
  },
});

const isOutgoing = index => index % 3 === 1;
</script>

<template>
  <div class="flex flex-col gap-3 p-4">
    <div
      v-for="n in count"
      :key="n"
      class="flex"
      :class="isOutgoing(n) ? 'justify-end' : 'justify-start'"
    >
      <div
        class="flex flex-col gap-1.5 rounded-xl p-3"
        :class="[
          isOutgoing(n)
            ? 'bg-n-slate-3 animate-pulse rounded-br-sm w-48'
            : 'bg-n-slate-3 animate-pulse rounded-bl-sm w-56',
        ]"
      >
        <div
          class="bg-n-slate-4 animate-pulse rounded h-3"
          :class="isOutgoing(n) ? 'w-36' : 'w-44'"
        />
        <div
          class="bg-n-slate-4 animate-pulse rounded h-3"
          :class="isOutgoing(n) ? 'w-24' : 'w-32'"
        />
      </div>
    </div>
  </div>
</template>
