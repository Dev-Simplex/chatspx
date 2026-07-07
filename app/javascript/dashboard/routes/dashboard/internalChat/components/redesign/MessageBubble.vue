<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  message: { type: Object, required: true },
});
</script>

<template>
  <div
    class="flex items-end gap-2"
    :class="message.mine ? 'flex-row-reverse' : 'flex-row'"
  >
    <Avatar
      v-if="!message.mine"
      :name="message.senderName || ''"
      :src="message.avatarSrc || ''"
      :size="28"
      rounded-full
      class="mb-1"
    />
    <div
      class="relative max-w-[78%] md:max-w-[68%] px-3.5 py-2 text-sm shadow-sm rounded-2xl break-words"
      :class="
        message.mine
          ? 'bg-n-brand text-white rounded-br-md'
          : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-md'
      "
    >
      <p class="whitespace-pre-wrap leading-relaxed">{{ message.content }}</p>
      <span
        class="flex items-center justify-end gap-1 mt-1 text-[10px] leading-none"
        :class="message.mine ? 'text-white/70' : 'text-n-slate-10'"
      >
        {{ message.time }}
        <span
          v-if="message.mine"
          class="text-sm"
          :class="message.read ? 'i-lucide-check-check' : 'i-lucide-check'"
        />
      </span>
    </div>
  </div>
</template>
