<script>
import NextButton from 'dashboard/components-next/button/Button.vue';
import EmptyState from '../../../../components/widgets/EmptyState.vue';

export default {
  components: {
    NextButton,
    EmptyState,
  },
};
</script>

<template>
  <div class="min-w-0 w-full p-6 lg:col-span-6">
    <EmptyState
      :title="$t('TEAMS_SETTINGS.FINISH.TITLE')"
      :message="$t('TEAMS_SETTINGS.FINISH.MESSAGE')"
      :button-text="$t('TEAMS_SETTINGS.FINISH.BUTTON_TEXT')"
    >
      <div class="w-full text-center">
        <router-link
          :to="{
            name: 'settings_teams_list',
          }"
        >
          <NextButton teal :label="$t('TEAMS_SETTINGS.FINISH.BUTTON_TEXT')" />
        </router-link>
      </div>
    </EmptyState>
  </div>
</template>
