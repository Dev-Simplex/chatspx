<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  channel: { type: Object, default: null },
});
const emit = defineEmits(['close', 'left']);

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);

const name = ref('');
const isSaving = ref(false);

const members = computed(() => props.channel?.members || []);
const allAgents = computed(() => store.getters['internalChat/getAgents']);
const addableAgents = computed(() =>
  allAgents.value.filter(a => !members.value.some(m => m.id === a.id))
);

const rename = async () => {
  const next = name.value.trim();
  if (!next || next === props.channel?.title) return;
  isSaving.value = true;
  try {
    await store.dispatch('internalChat/renameChannel', {
      channelId: props.channel.id,
      name: next,
    });
    useAlert(t('INTERNAL_CHAT.MANAGE.RENAMED'));
  } finally {
    isSaving.value = false;
  }
};

const addMember = async agent => {
  await store.dispatch('internalChat/addMember', {
    channelId: props.channel.id,
    userId: agent.id,
  });
};

const removeMember = async member => {
  await store.dispatch('internalChat/removeMember', {
    channelId: props.channel.id,
    userId: member.id,
  });
};

const leave = async () => {
  await store.dispatch('internalChat/leaveChannel', props.channel.id);
  emit('left', props.channel.id);
  emit('close');
};

const close = () => emit('close');

watch(
  () => props.show,
  show => {
    if (show) {
      name.value = props.channel?.title || '';
      store.dispatch('internalChat/fetchAgents');
      nextTick(() => setTimeout(() => dialogRef.value?.open?.(), 10));
    } else {
      dialogRef.value?.close?.();
    }
  },
  { immediate: true }
);
</script>

<template>
  <Dialog
    v-if="show && channel"
    ref="dialogRef"
    :title="t('INTERNAL_CHAT.MANAGE.TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="md"
    @close="close"
  >
    <div class="space-y-5">
      <!-- rename -->
      <div>
        <label
          class="block text-xs font-medium uppercase text-n-slate-10 mb-1.5"
        >
          {{ t('INTERNAL_CHAT.MANAGE.NAME') }}
        </label>
        <div class="flex gap-2">
          <input
            v-model="name"
            type="text"
            class="flex-1 px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 focus:outline-none focus:border-n-brand"
            @keydown.enter.prevent="rename"
          />
          <Button
            color="blue"
            :is-loading="isSaving"
            :disabled="!name.trim() || name.trim() === channel.title"
            @click="rename"
          >
            {{ t('INTERNAL_CHAT.MANAGE.SAVE') }}
          </Button>
        </div>
      </div>

      <!-- members -->
      <div>
        <label
          class="block text-xs font-medium uppercase text-n-slate-10 mb-1.5"
        >
          {{ t('INTERNAL_CHAT.MANAGE.MEMBERS', { count: members.length }) }}
        </label>
        <div class="space-y-1 max-h-44 overflow-y-auto">
          <div
            v-for="member in members"
            :key="member.id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-n-alpha-1"
          >
            <Avatar
              :src="member.avatar_url"
              :name="member.name"
              :size="26"
              rounded-full
            />
            <span class="flex-1 text-sm text-n-slate-12 truncate">
              {{ member.name }}
            </span>
            <button
              class="i-lucide-x text-n-slate-10 hover:text-n-ruby-11"
              :title="t('INTERNAL_CHAT.MANAGE.REMOVE')"
              @click="removeMember(member)"
            />
          </div>
        </div>
      </div>

      <!-- add member -->
      <div v-if="addableAgents.length">
        <label
          class="block text-xs font-medium uppercase text-n-slate-10 mb-1.5"
        >
          {{ t('INTERNAL_CHAT.MANAGE.ADD') }}
        </label>
        <div class="space-y-1 max-h-40 overflow-y-auto">
          <button
            v-for="agent in addableAgents"
            :key="agent.id"
            class="flex items-center gap-2.5 w-full px-2 py-1.5 rounded-lg text-sm text-n-slate-12 hover:bg-n-alpha-1"
            @click="addMember(agent)"
          >
            <Avatar
              :src="agent.avatar_url"
              :name="agent.name"
              :size="24"
              rounded-full
            />
            <span class="flex-1 text-left truncate">{{ agent.name }}</span>
            <span class="i-lucide-plus text-n-slate-10" />
          </button>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-between items-center w-full">
        <Button variant="ghost" color="ruby" @click="leave">
          {{ t('INTERNAL_CHAT.MANAGE.LEAVE') }}
        </Button>
        <Button variant="ghost" @click="close">
          {{ t('INTERNAL_CHAT.CANCEL') }}
        </Button>
      </div>
    </template>
  </Dialog>
</template>
