<script>
import { mapGetters } from 'vuex';

const VISIBILITY_OPTIONS = ['everyone', 'personal', 'team'];

export default {
  props: {
    visibility: {
      type: String,
      default: 'everyone',
    },
    teamId: {
      type: [Number, String],
      default: null,
    },
    // Surfaces the "select a team" validation error from the parent form.
    teamError: {
      type: String,
      default: '',
    },
    // When true the whole field is read-only (e.g. a non-author cannot change the
    // visibility of a public response — mirrors validate_visibility_change on the backend).
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:visibility', 'update:teamId'],
  computed: {
    ...mapGetters({
      myTeams: 'teams/getMyTeams',
      allTeams: 'teams/getTeams',
      currentRole: 'getCurrentRole',
    }),
    isAdmin() {
      return this.currentRole === 'administrator';
    },
    // Admins may target any team; agents are limited to their own teams.
    availableTeams() {
      return this.isAdmin ? this.allTeams : this.myTeams;
    },
    options() {
      return VISIBILITY_OPTIONS.map(value => ({
        value,
        label: this.$t(`CANNED_MGMT.VISIBILITY.${value.toUpperCase()}.LABEL`),
        description: this.$t(
          `CANNED_MGMT.VISIBILITY.${value.toUpperCase()}.DESCRIPTION`
        ),
      }));
    },
  },
  mounted() {
    if (!this.allTeams.length) {
      this.$store.dispatch('teams/get');
    }
  },
  methods: {
    onSelectVisibility(value) {
      if (this.disabled) return;
      this.$emit('update:visibility', value);
      // Clear the team when leaving team-visibility so a stale team_id is not submitted.
      if (value !== 'team') {
        this.$emit('update:teamId', null);
      }
    },
    onSelectTeam(event) {
      const { value } = event.target;
      this.$emit('update:teamId', value ? Number(value) : null);
    },
  },
};
</script>

<template>
  <div class="w-full">
    <label class="block">
      {{ $t('CANNED_MGMT.VISIBILITY.LABEL') }}
    </label>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
      <button
        v-for="option in options"
        :key="option.value"
        v-tooltip.top="option.description"
        type="button"
        class="p-2 relative rounded-md border border-solid justify-start items-start gap-1 flex flex-col text-start"
        :class="[
          visibility === option.value
            ? 'bg-n-blue-2 dark:bg-n-blue-1 border-n-blue-3 dark:border-n-blue-4'
            : 'bg-n-solid-1 border-n-weak dark:border-n-strong',
          disabled ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer',
        ]"
        :disabled="disabled"
        @click="onSelectVisibility(option.value)"
      >
        <span class="block text-heading-3 text-n-slate-12 line-clamp-1">
          {{ option.label }}
        </span>
        <span class="text-n-slate-11 text-label-small">
          {{ option.description }}
        </span>
      </button>
    </div>

    <div v-if="visibility === 'team'" class="w-full mt-3">
      <label class="block" :class="{ error: !!teamError }">
        {{ $t('CANNED_MGMT.VISIBILITY.TEAM_SELECT.LABEL') }}
        <select
          :value="teamId || ''"
          class="reset-base"
          :disabled="disabled"
          @change="onSelectTeam"
        >
          <option value="" disabled>
            {{ $t('CANNED_MGMT.VISIBILITY.TEAM_SELECT.PLACEHOLDER') }}
          </option>
          <option
            v-for="team in availableTeams"
            :key="team.id"
            :value="team.id"
          >
            {{ team.name }}
          </option>
        </select>
        <span v-if="teamError" class="message">
          {{ teamError }}
        </span>
      </label>
    </div>
  </div>
</template>
