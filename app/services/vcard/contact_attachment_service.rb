# Single, reusable entry point for the "a .vcf attachment should render as a
# contact card" rule. Detects whether an uploaded file is a vCard, parses it,
# and builds one `:contact` attachment per contact found (consistent with the
# official WhatsApp Cloud channel, which emits one contact per card).
#
# Usage (any inbound channel that receives raw uploads):
#   handled = Vcard::ContactAttachmentService.new(message: msg, uploaded_file: file).build
#   # fall back to the default attachment handling when `handled` is false
class Vcard::ContactAttachmentService
  include FileTypeHelper

  def initialize(message:, uploaded_file:)
    @message = message
    @uploaded_file = uploaded_file
  end

  # Returns true when the file was a vCard and contact attachment(s) were
  # built; false otherwise (the caller keeps its normal attachment handling).
  def build
    return false unless vcard?

    contacts = parse_contacts
    return false if contacts.blank?

    contacts.each { |contact| build_contact_attachment(contact) }
    true
  end

  private

  def vcard?
    vcard_attachment?(content_type, filename)
  end

  def content_type
    @uploaded_file.try(:content_type)
  end

  def filename
    @uploaded_file.try(:original_filename)
  end

  def parse_contacts
    return [] if raw_text.blank?

    Vcard::ParserService.new(raw_text).parse
  end

  def raw_text
    return @raw_text if defined?(@raw_text)

    @raw_text = read_file
  end

  def read_file
    io = @uploaded_file.respond_to?(:tempfile) ? @uploaded_file.tempfile : @uploaded_file
    io.rewind if io.respond_to?(:rewind)
    content = io.read
    io.rewind if io.respond_to?(:rewind)
    content&.dup&.force_encoding('UTF-8')
  rescue StandardError => e
    Rails.logger.warn("[Vcard::ContactAttachmentService] failed to read vCard: #{e.class}: #{e.message}")
    nil
  end

  def build_contact_attachment(contact)
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: :contact,
      fallback_title: contact[:phone].to_s,
      meta: contact_meta(contact)
    )
  end

  # Keys are stored already camelCased so they survive the frontend's deep
  # camelCase transform unchanged (matches the official WhatsApp channel which
  # writes :firstName / :lastName).
  def contact_meta(contact)
    {
      firstName: contact[:first_name],
      lastName: contact[:last_name],
      fullName: contact[:full_name],
      organization: contact[:organization],
      email: contact[:email],
      photo: contact[:photo]
    }.compact
  end
end
