class RepurposeInsertArticleInReplyForBrandedEmailTemplates < ActiveRecord::Migration[7.1]
  # No-op: insert_article_in_reply remains a valid primary-column flag in ChatSPX;
  # branded_email_templates has its own feature_flags_ext_1 bit.
  def up; end
end
