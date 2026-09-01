<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  selectedTeam: {
    type: Object,
    default: null,
  },
  teams: {
    type: Array,
    default: () => [],
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  showTeamsDropdown: {
    type: Boolean,
    required: true,
  },
});

const emit = defineEmits(['updateTeam', 'toggleDropdown']);

const { t } = useI18n();

const teamsList = computed(() =>
  props.teams.map(({ id, name }) => ({
    id,
    label: name,
    value: id,
    action: 'team',
    icon: 'i-lucide-users',
  }))
);

const handleTeamAction = ({ value }) => {
  emit('updateTeam', props.teams.find(team => team.id === value) || null);
  emit('toggleDropdown', false);
};
</script>

<template>
  <div class="relative px-5 pb-4 overflow-y-visible">
    <div
      v-if="selectedTeam"
      class="inline-flex items-center gap-2 rounded-xl border border-n-weak/80 bg-n-alpha-3 shadow-sm px-3 py-2 min-h-10 min-w-0 max-w-full"
    >
      <span
        class="i-lucide-users size-4 text-n-slate-11 flex-shrink-0"
        aria-hidden="true"
      />
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{ selectedTeam.name }}
      </span>
      <Button
        variant="ghost"
        icon="i-lucide-x"
        color="slate"
        size="xs"
        class="flex-shrink-0 ltr:ml-1 rtl:mr-1"
        @click="emit('updateTeam', null)"
      />
    </div>
    <div
      v-else
      v-on-click-outside="() => emit('toggleDropdown', false)"
      class="relative"
    >
      <button
        type="button"
        :disabled="disabled"
        class="w-full flex items-center gap-3 px-4 py-3 rounded-xl border border-dashed border-n-strong bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11 transition-colors duration-150 hover:bg-n-brand/5 hover:border-n-brand/40 disabled:opacity-50 disabled:cursor-not-allowed"
        @click="emit('toggleDropdown', !showTeamsDropdown)"
      >
        <span class="i-lucide-users size-4" aria-hidden="true" />
        <span class="text-sm font-medium">
          {{ t('COMPOSE_NEW_CONVERSATION.FORM.TEAM_SELECTOR.BUTTON') }}
        </span>
        <span
          class="i-lucide-chevron-down size-4 ltr:ml-auto rtl:mr-auto"
          aria-hidden="true"
        />
      </button>
      <DropdownMenu
        v-if="showTeamsDropdown"
        :menu-items="teamsList"
        class="ltr:left-0 rtl:right-0 z-[100] top-12 overflow-y-auto max-h-56 w-full dark:!outline-n-slate-5"
        @action="handleTeamAction"
      />
    </div>
  </div>
</template>
