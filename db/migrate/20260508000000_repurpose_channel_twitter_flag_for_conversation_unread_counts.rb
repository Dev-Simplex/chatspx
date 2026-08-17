class RepurposeChannelTwitterFlagForConversationUnreadCounts < ActiveRecord::Migration[7.1]
  # No-op: channel_twitter remains a valid primary-column flag in ChatSPX;
  # conversation_unread_counts has its own feature_flags_ext_1 bit.
  def up; end
end
