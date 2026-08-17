class RepurposeTwilioContentTemplatesFlagForCaptainDocumentAutoSync < ActiveRecord::Migration[7.1]
  # No-op: twilio_content_templates remains a valid primary-column flag in ChatSPX;
  # captain_document_auto_sync has its own feature_flags_ext_1 bit.
  def up; end
end
