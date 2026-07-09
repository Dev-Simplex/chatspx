<script>
import { ref } from 'vue';
import { mapGetters } from 'vuex';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import Spinner from 'shared/components/Spinner.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import AddLabel from 'shared/components/ui/dropdown/AddLabel.vue';

export default {
  components: {
    Spinner,
    LabelDropdown,
    AddLabel,
  },
  setup() {
    const {
      savedLabels,
      activeLabels,
      accountLabels,
      addLabelToConversation,
      removeLabelFromConversation,
    } = useConversationLabels();

    const showSearchDropdownLabel = ref(false);

    const toggleLabels = () => {
      showSearchDropdownLabel.value = !showSearchDropdownLabel.value;
    };

    const closeDropdownLabel = () => {
      showSearchDropdownLabel.value = false;
    };

    const keyboardEvents = {
      KeyL: {
        action: e => {
          e.preventDefault();
          toggleLabels();
        },
      },
      Escape: {
        action: () => {
          if (showSearchDropdownLabel.value) {
            toggleLabels();
          }
        },
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);
    return {
      savedLabels,
      activeLabels,
      accountLabels,
      addLabelToConversation,
      removeLabelFromConversation,
      showSearchDropdownLabel,
      closeDropdownLabel,
      toggleLabels,
    };
  },
  data() {
    return {
      selectedLabels: [],
    };
  },

  computed: {
    ...mapGetters({
      conversationUiFlags: 'conversationLabels/getUIFlags',
    }),
  },
};
</script>

<template>
  <div class="sidebar-labels-wrap">
    <div
      v-if="!conversationUiFlags.isFetching"
      class="contact-conversation--list"
    >
      <div
        v-on-clickaway="closeDropdownLabel"
        class="label-wrap flex flex-wrap gap-1.5"
        @keyup.esc="closeDropdownLabel"
      >
        <AddLabel @add="toggleLabels" />
        <woot-label
          v-for="label in activeLabels"
          :key="label.id"
          :title="label.title"
          :description="label.description"
          show-close
          :color="label.color"
          variant="smooth"
          class="max-w-[calc(100%-0.5rem)]"
          @remove="removeLabelFromConversation"
        />

        <div
          :class="{
            'block visible': showSearchDropdownLabel,
            'hidden invisible': !showSearchDropdownLabel,
          }"
          class="border rounded-lg bg-n-solid-1 dark:bg-[#233138] top-6 absolute w-full shadow-[0_2px_8px_rgba(11,20,26,0.12)] border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] p-2 box-border z-[9999]"
        >
          <LabelDropdown
            v-if="showSearchDropdownLabel"
            :account-labels="accountLabels"
            :selected-labels="savedLabels"
            allow-creation
            @add="addLabelToConversation"
            @remove="removeLabelFromConversation"
          />
        </div>
      </div>
    </div>
    <Spinner v-else />
  </div>
</template>

<style lang="scss" scoped>
.sidebar-labels-wrap {
  margin-bottom: 0;
}
.contact-conversation--list {
  width: 100%;

  .label-wrap {
    position: relative;
  }
}
</style>
