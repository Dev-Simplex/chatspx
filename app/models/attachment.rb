# == Schema Information
#
# Table name: attachments
#
#  id               :integer          not null, primary key
#  coordinates_lat  :float            default(0.0)
#  coordinates_long :float            default(0.0)
#  extension        :string
#  external_url     :string
#  fallback_title   :string
#  file_type        :integer          default("image")
#  meta             :jsonb
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :integer          not null
#  message_id       :integer          not null
#
# Indexes
#
#  index_attachments_on_account_id  (account_id)
#  index_attachments_on_message_id  (message_id)
#

class Attachment < ApplicationRecord
  include Rails.application.routes.url_helpers

  ACCEPTABLE_FILE_TYPES = %w[
    text/csv text/plain text/rtf text/xml
    application/json application/pdf
    application/xml
    application/zip application/x-7z-compressed application/vnd.rar application/x-tar
    application/msword application/vnd.ms-excel application/vnd.ms-powerpoint application/rtf
    application/vnd.oasis.opendocument.text
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/x-pkcs12 application/pkcs12
  ].freeze
  ACCEPTABLE_FILE_EXTENSIONS = %w[pfx xml].freeze
  GENERIC_FILE_CONTENT_TYPES = %w[application/octet-stream].freeze
  belongs_to :account
  belongs_to :message
  has_one_attached :file
  before_save :set_extension
  validate :acceptable_file
  validates :external_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  enum file_type: { :image => 0, :audio => 1, :video => 2, :file => 3, :location => 4, :fallback => 5, :share => 6, :story_mention => 7,
                    :contact => 8, :ig_reel => 9, :ig_post => 10, :ig_story => 11, :embed => 12 }

  after_create_commit :schedule_audio_transcription
  after_create_commit :schedule_waveform_generation

  def push_event_data
    return unless file_type

    base_data.merge(metadata_for_file_type)
  end

  # NOTE: the URl returned does a 301 redirect to the actual file
  def file_url
    file.attached? ? url_for(file) : ''
  end

  # NOTE: for External services use this methods since redirect doesn't work effectively in a lot of cases
  def download_url
    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    file.attached? ? file.blob.url : ''
  end

  def thumb_url
    return '' unless file.attached? && image?

    begin
      url_for(file.representation(resize_to_fill: [250, nil]))
    rescue ActiveStorage::UnrepresentableError => e
      Rails.logger.warn "Unrepresentable image attachment: #{id} (#{file.filename}) - #{e.message}"
      ''
    end
  end

  def with_attached_file?
    [:image, :audio, :video, :file].include?(file_type.to_sym)
  end

  private

  def metadata_for_file_type
    case file_type.to_sym
    when :location
      location_metadata
    when :fallback
      fallback_data
    when :contact
      contact_metadata
    when :audio
      audio_metadata
    when :embed
      embed_data
    else
      file.attached? ? file_metadata : { data_url: external_url, thumb_url: '' }
    end
  end

  def embed_data
    {
      data_url: external_url
    }
  end

  def audio_metadata
    # `file_metadata` reads `file.byte_size` / `file.metadata[:width]`, which blow up when no file
    # is attached — and an audio row can legitimately exist without one: the builders save the
    # attachment BEFORE downloading the media, so any failed download leaves the row behind. Since
    # push_event_data feeds the messages endpoint, one such row used to 500 the WHOLE conversation.
    # Same guard the generic branch already applies in `metadata_for_file_type`.
    audio_file_data = base_data.merge(file.attached? ? file_metadata : { data_url: external_url, thumb_url: '' })
    audio_file_data[:data_url] = inline_audio_url if file.attached?
    audio_file_data[:transcribed_text] = meta&.[]('transcribed_text') || ''

    peaks = meta&.[]('waveform_peaks')
    audio_file_data[:waveform_peaks] = peaks if peaks.is_a?(Array) && peaks.any?

    audio_file_data
  end

  def inline_audio_url
    return '' unless file.attached?

    Rails.application.routes.url_helpers.rails_storage_redirect_url(file, disposition: 'inline')
  end

  def file_metadata
    metadata = {
      extension: extension,
      content_type: file.content_type,
      data_url: file_url,
      thumb_url: thumb_url,
      file_size: file.byte_size,
      width: file.metadata[:width],
      height: file.metadata[:height]
    }

    metadata[:data_url] = metadata[:thumb_url] = external_url if instagram_incoming_message?
    metadata
  end

  def location_metadata
    # Defensive defaults: external integrations (e.g. WAHA Chatwoot App) call
    # `.split` on these fields and crash when null. Empty strings are safe.
    {
      coordinates_lat: coordinates_lat,
      coordinates_long: coordinates_long,
      fallback_title: fallback_title.to_s,
      data_url: external_url.to_s,
      thumb_url: '',
      extension: '',
      file_size: 0
    }
  end

  def fallback_data
    {
      fallback_title: fallback_title,
      data_url: external_url
    }
  end

  def base_data
    {
      id: id,
      message_id: message_id,
      file_type: file_type,
      account_id: account_id
    }
  end

  def contact_metadata
    # Defensive defaults — same rationale as location_metadata.
    {
      fallback_title: fallback_title.to_s,
      meta: meta || {},
      data_url: '',
      thumb_url: '',
      extension: 'vcf',
      file_size: 0
    }
  end

  # Hard ceiling (in MB) for any attachment upload, mirroring the frontend
  # HARD_MAXIMUM_FILE_UPLOAD_SIZE. Files above this never go through, no matter
  # the channel or the configured MAXIMUM_FILE_UPLOAD_SIZE.
  HARD_MAXIMUM_FILE_UPLOAD_SIZE_MB = 100

  # Per-category WAHA (Channel::Api) limits, in MB — mirrors the frontend
  # WAHA_MAX_SIZE_BY_CATEGORY (shared/helpers/FileHelper.js). Server-side net so
  # oversized media for the channel never gets saved and then rejected by the
  # WhatsApp engine at send time. Only applied to Channel::Api.
  WAHA_MAX_SIZE_BY_CATEGORY_MB = { 'image' => 16, 'video' => 16, 'audio' => 16, 'document' => 100 }.freeze

  def instagram_incoming_message?
    return false unless message.incoming?

    return true if message.inbox.instagram_direct?

    message.inbox.instagram? && message.conversation&.additional_attributes&.dig('type') == 'instagram_direct_message'
  end

  def set_extension
    return unless file.attached?
    return if extension.present?

    self.extension = File.extname(file.filename.to_s).delete_prefix('.').presence
  end

  def should_validate_file?
    return unless file.attached?
    # we are only limiting attachment types in case of website widget
    return unless message.inbox.channel_type == 'Channel::WebWidget'

    true
  end

  def acceptable_file
    return unless file.attached?

    # Size is validated for every channel (defense in depth: keeps oversized
    # files from being saved and then failing silently at send time).
    validate_file_size(file.byte_size)
    # Stricter per-category net for WAHA (e.g. video > 16 MB), mirroring the front.
    validate_waha_category_size(file.byte_size, file.content_type)
    # Type stays restricted to the website widget, as before.
    validate_file_content_type(file.content_type) if should_validate_file?
  end

  def validate_file_content_type(file_content_type)
    return if media_file?(file_content_type) || ACCEPTABLE_FILE_TYPES.include?(file_content_type)
    return if generic_file_content_type?(file_content_type) && ACCEPTABLE_FILE_EXTENSIONS.include?(file_extension)

    errors.add(:file, 'type not supported')
  end

  def validate_file_size(byte_size)
    errors.add(:file, "size exceeds the #{max_upload_size_mb}MB limit") if byte_size > max_upload_size_mb.megabytes
  end

  # WAHA per-category size net. No-op for every other channel (do-no-harm) and
  # for mimes without a known category.
  def validate_waha_category_size(byte_size, content_type)
    return unless message&.inbox&.channel_type == 'Channel::Api'

    category = waha_category_from_mime(content_type)
    limit_mb = WAHA_MAX_SIZE_BY_CATEGORY_MB[category]
    return if limit_mb.nil?

    errors.add(:file, "size exceeds the #{limit_mb}MB limit for #{category}") if byte_size > limit_mb.megabytes
  end

  # Mirrors categoryFromMime in FileHelper.js: application/* and text/* →
  # document; otherwise the mime head (image / video / audio).
  def waha_category_from_mime(content_type)
    head = content_type.to_s.split('/').first
    return 'document' if %w[application text].include?(head)

    head.presence
  end

  # min(configured limit, hard 100MB ceiling). A smaller configured limit
  # (e.g. SMS-tuned installs) is still respected; larger/unset is capped at 100.
  def max_upload_size_mb
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0

    [limit_mb, HARD_MAXIMUM_FILE_UPLOAD_SIZE_MB].min
  end

  def media_file?(file_content_type)
    file_content_type.to_s.start_with?('image/', 'video/', 'audio/')
  end

  def generic_file_content_type?(file_content_type)
    file_content_type.blank? || GENERIC_FILE_CONTENT_TYPES.include?(file_content_type)
  end

  def file_extension
    File.extname(file.filename.to_s).delete_prefix('.').downcase
  end

  def schedule_audio_transcription
    return unless file_type.to_s == 'audio'
    return if message.blank? || !message.incoming?
    return unless account&.audio_transcriptions

    AudioTranscriptionJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.warn("[Attachment#schedule_audio_transcription] #{e.class}: #{e.message}")
  end

  def schedule_waveform_generation
    return unless file_type.to_s == 'audio'

    Audio::WaveformGenerationJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.warn("[Attachment#schedule_waveform_generation] #{e.class}: #{e.message}")
  end
end

Attachment.include_mod_with('Concerns::Attachment')
