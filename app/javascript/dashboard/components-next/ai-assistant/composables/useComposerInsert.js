import { computed } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { useMapGetter } from 'dashboard/composables/store';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

/**
 * "Use as reply" — pushes the AI answer into the conversation composer.
 *
 * This reuses the exact path the legacy Copilot already uses
 * (`CopilotAssistantMessage.vue:52-59`): a mitt event picked up by
 * `ReplyBox.addIntoEditor` (plain textarea) or `Editor.insertContentIntoEditor`
 * (ProseMirror). Web widget and e-mail inboxes get the rich editor, everything
 * else gets the plain one — same rule as the legacy component, so behaviour is
 * identical across both panels.
 */

const RICH_EDITOR_INBOXES = [INBOX_TYPES.WEB, INBOX_TYPES.EMAIL];

export function useComposerInsert() {
  const currentChat = useMapGetter('getSelectedChat');

  const channelType = computed(() => {
    return (
      currentChat.value?.meta?.channel ||
      currentChat.value?.inbox?.channel_type ||
      ''
    );
  });

  const usesRichEditor = computed(() =>
    RICH_EDITOR_INBOXES.includes(channelType.value)
  );

  /**
   * @param {string} text
   * @returns {boolean} false when there was nothing to insert
   */
  function insertIntoComposer(text) {
    const content = (text || '').trim();
    if (!content) return false;
    emitter.emit(
      usesRichEditor.value
        ? BUS_EVENTS.INSERT_INTO_RICH_EDITOR
        : BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
      content
    );
    return true;
  }

  return { insertIntoComposer, usesRichEditor, channelType };
}
