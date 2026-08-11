<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import validations, { getLabelTitleError } from './validations';
import { useVuelidate } from '@vuelidate/core';

import NextButton from 'dashboard/components-next/button/Button.vue';
import LabelVisibilityField from './LabelVisibilityField.vue';

export default {
  components: {
    NextButton,
    LabelVisibilityField,
  },
  props: {
    selectedResponse: {
      type: Object,
      default: () => {},
    },
  },
  emits: ['close'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      title: '',
      description: '',
      showOnSidebar: true,
      color: '',
      visibility: 'everyone',
      teamId: null,
    };
  },
  validations,
  computed: {
    ...mapGetters({
      uiFlags: 'labels/getUIFlags',
      currentUser: 'getCurrentUser',
      currentRole: 'getCurrentRole',
      myTeams: 'teams/getMyTeams',
    }),
    pageTitle() {
      return `${this.$t('LABEL_MGMT.EDIT.TITLE')} - ${
        this.selectedResponse.title
      }`;
    },
    labelTitleErrorMessage() {
      const { key, values } = getLabelTitleError(this.v$, this.title);
      return key ? this.$t(key, values) : '';
    },
    teamErrorMessage() {
      return this.v$.teamId.$error
        ? this.$t('LABEL_MGMT.FORM.VISIBILITY.TEAM_SELECT.REQUIRED_ERROR')
        : '';
    },
    // Mirrors the backend LabelPolicy#manage? rule so the form does not frustrate.
    canManage() {
      const label = this.selectedResponse || {};
      if (this.currentRole === 'administrator') return true;
      const isAuthor =
        !!label.created_by && this.currentUser?.id === label.created_by.id;
      if (label.visibility === 'team') {
        return this.myTeams.some(team => team.id === label.team_id);
      }
      return isAuthor;
    },
  },
  mounted() {
    this.setFormValues();
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    setFormValues() {
      this.title = this.selectedResponse.title;
      this.description = this.selectedResponse.description;
      this.showOnSidebar = this.selectedResponse.show_on_sidebar;
      this.color = this.selectedResponse.color;
      this.visibility = this.selectedResponse.visibility || 'everyone';
      this.teamId = this.selectedResponse.team_id || null;
    },
    editLabel() {
      this.$store
        .dispatch('labels/update', {
          id: this.selectedResponse.id,
          color: this.color,
          description: this.description,
          title: this.title.toLowerCase(),
          show_on_sidebar: this.showOnSidebar,
          visibility: this.visibility,
          team_id: this.visibility === 'team' ? this.teamId : null,
        })
        .then(() => {
          useAlert(this.$t('LABEL_MGMT.EDIT.API.SUCCESS_MESSAGE'));
          setTimeout(() => this.onClose(), 10);
        })
        .catch(() => {
          useAlert(this.$t('LABEL_MGMT.EDIT.API.ERROR_MESSAGE'));
        });
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <div
      v-if="!canManage"
      class="flex items-start w-full p-2 mt-2 rounded-md bg-n-alpha-1 dark:bg-n-solid-3"
    >
      <p class="mb-0 text-n-slate-11 text-body-para">
        {{ $t('LABEL_MGMT.FORM.NO_MANAGE_PERMISSION') }}
      </p>
    </div>
    <form class="flex flex-wrap mx-0" @submit.prevent="editLabel">
      <woot-input
        v-model="title"
        :class="{ error: v$.title.$error }"
        class="w-full label-name--input"
        :label="$t('LABEL_MGMT.FORM.NAME.LABEL')"
        :placeholder="$t('LABEL_MGMT.FORM.NAME.PLACEHOLDER')"
        :error="labelTitleErrorMessage"
        @input="v$.title.$touch"
        @blur="v$.title.$touch"
      />
      <woot-input
        v-model="description"
        :class="{ error: v$.description.$error }"
        class="w-full"
        :label="$t('LABEL_MGMT.FORM.DESCRIPTION.LABEL')"
        :placeholder="$t('LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER')"
        @input="v$.description.$touch"
        @blur="v$.description.$touch"
      />

      <div class="w-full">
        <label>
          {{ $t('LABEL_MGMT.FORM.COLOR.LABEL') }}
          <woot-color-picker v-model="color" />
        </label>
      </div>

      <LabelVisibilityField
        v-model:visibility="visibility"
        v-model:team-id="teamId"
        :team-error="teamErrorMessage"
      />

      <div class="flex items-center w-full gap-2 mt-3">
        <input v-model="showOnSidebar" type="checkbox" :value="true" />
        <label for="conversation_creation">
          {{ $t('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL') }}
        </label>
      </div>
      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('LABEL_MGMT.FORM.CANCEL')"
          @click.prevent="onClose"
        />
        <NextButton
          type="submit"
          :label="$t('LABEL_MGMT.FORM.EDIT')"
          :disabled="
            !canManage ||
            v$.title.$invalid ||
            v$.teamId.$invalid ||
            uiFlags.isUpdating
          "
          :is-loading="uiFlags.isUpdating"
        />
      </div>
    </form>
  </div>
</template>

<style lang="scss" scoped>
// Label API supports only lowercase letters
.label-name--input {
  ::v-deep {
    input {
      @apply lowercase;
    }
  }
}
</style>
