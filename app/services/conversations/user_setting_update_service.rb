class Conversations::UserSettingUpdateService
  # Allowed keys inside user_settings.{user_id}. theme_key validation deferida para PR G14.
  ALLOWED_KEYS = %w[pinned archived_at muted_until theme_key].freeze
  ISO_DATETIME_KEYS = %w[archived_at muted_until].freeze
  BOOLEAN_KEYS = %w[pinned].freeze
  STRING_KEYS = %w[theme_key].freeze

  class ValidationError < StandardError; end

  def initialize(conversation:, user_id:, patch:)
    @conversation = conversation
    @user_id = user_id
    @patch = patch.is_a?(Hash) ? patch.deep_stringify_keys : {}
  end

  # Atomic merge inside Postgres: jsonb_set + (existing_node || patch) — anti-race-condition.
  # If two requests update different keys concurrently, both survive (no lost update).
  def perform
    sanitized = sanitize_patch(@patch)
    raise ValidationError, 'patch must contain at least one allowed key' if sanitized.empty?

    sql = <<~SQL.squish
      additional_attributes = jsonb_set(
        coalesce(additional_attributes, '{}'::jsonb),
        ARRAY['user_settings', ?],
        coalesce(coalesce(additional_attributes, '{}'::jsonb) #> ARRAY['user_settings', ?], '{}'::jsonb) || ?::jsonb,
        true
      )
    SQL

    Conversation.where(id: @conversation.id).update_all([sql, @user_id.to_s, @user_id.to_s, sanitized.to_json])

    @conversation.reload
    dispatch_event
    @conversation.user_setting_for(@user_id)
  end

  # Removes the entire user_settings.{user_id} node.
  def destroy
    Conversation.where(id: @conversation.id).update_all([
                                                          'additional_attributes = ' \
                                                          "additional_attributes #- ARRAY['user_settings', ?]",
                                                          @user_id.to_s
                                                        ])
    @conversation.reload
    dispatch_event
    {}
  end

  private

  def sanitize_patch(patch)
    patch.each_with_object({}) do |(key, value), acc|
      key = key.to_s
      next unless ALLOWED_KEYS.include?(key)

      acc[key] = coerce_value(key, value)
    end
  end

  def coerce_value(key, value)
    return nil if value.nil?

    if BOOLEAN_KEYS.include?(key)
      coerce_boolean(key, value)
    elsif ISO_DATETIME_KEYS.include?(key)
      coerce_iso_datetime(key, value)
    elsif STRING_KEYS.include?(key)
      value.is_a?(String) ? value : (raise ValidationError, "#{key} must be a string")
    else
      value
    end
  end

  def coerce_boolean(key, value)
    return value if [true, false].include?(value)

    raise ValidationError, "#{key} must be boolean"
  end

  def coerce_iso_datetime(key, value)
    unless value.is_a?(String)
      raise ValidationError, "#{key} must be an ISO8601 string"
    end

    Time.iso8601(value)
    value
  rescue ArgumentError
    raise ValidationError, "#{key} must be a valid ISO8601 datetime string"
  end

  def dispatch_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::CONVERSATION_USER_SETTING_CHANGED,
      Time.zone.now,
      conversation: @conversation,
      user_id: @user_id,
      performed_by: Current.executed_by
    )
  end
end
