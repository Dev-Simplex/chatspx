class RepurposeQuotedEmailReplyFlagForUnreadCountForFilters < ActiveRecord::Migration[7.1]
  # No-op: quoted_email_reply remains a valid primary-column flag in ChatSPX;
  # unread_count_for_filters has its own feature_flags_ext_1 bit.
  def up; end
end
