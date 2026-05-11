<script setup>
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';

defineProps({
  contextMenuPosition: {
    type: Object,
    default: () => ({}),
  },
  menuItems: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close', 'selectAction']);

const handleClose = () => {
  emit('close');
};

const onMenuItemClick = key => {
  emit('selectAction', key);
  handleClose();
};
</script>

<template>
  <ContextMenu
    :x="contextMenuPosition.x"
    :y="contextMenuPosition.y"
    @close="handleClose"
  >
    <div
      class="p-1 rounded-md shadow-[0_2px_8px_rgba(11,20,26,0.12)] bg-n-solid-1 dark:bg-[#233138] border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)]"
    >
      <MenuItem
        v-for="item in menuItems"
        :key="item.key"
        :option="item"
        variant="icon"
        class="!w-48"
        @click.stop="onMenuItemClick(item.key)"
      />
    </div>
  </ContextMenu>
</template>
