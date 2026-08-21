class Conversations::UserSettingUpdateService
  # Allowed keys inside user_settings.{user_id}.
  ALLOWED_KEYS = %w[pinned archived_at muted_until theme_key].freeze
  ISO_DATETIME_KEYS = %w[archived_at muted_until].freeze
  BOOLEAN_KEYS = %w[pinned].freeze
  STRING_KEYS = %w[theme_key].freeze

  # Whitelist of accepted theme_key values for per-chat themes (PR G14).
  # Source of truth: chatspx-mobile/src/constants/wallpapers.ts (Story 6.5 will mirror this list).
  # nil is also accepted to clear the theme back to default.
  ALLOWED_THEME_KEYS = %w[
    default
    dark_emerald
    wallpaper_doodle
    midnight
    forest
    sunset
    ocean
    plain_white
    plain_dark
  ].freeze

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

    # `jsonb_set` com create_missing=true cria APENAS o ultimo elemento do caminho: se a chave
    # intermediaria `user_settings` nao existe, ele devolve o alvo INTACTO e sem erro. Como
    # nada mais cria esse no, a PRIMEIRA gravacao de cada conversa era um no-op silencioso —
    # `update_all` retornava 1 linha afetada e a coluna continuava `{}`. O `jsonb_set` de dentro
    # garante o pai (com o valor atual, ou `{}`) para o de fora ter onde escrever.
    sql = <<~SQL.squish
      additional_attributes = jsonb_set(
        jsonb_set(
          coalesce(additional_attributes, '{}'::jsonb),
          ARRAY['user_settings'],
          coalesce(coalesce(additional_attributes, '{}'::jsonb) -> 'user_settings', '{}'::jsonb),
          true
        ),
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
      coerce_string(key, value)
    else
      value
    end
  end

  def coerce_string(key, value)
    raise ValidationError, "#{key} must be a string" unless value.is_a?(String)

    validate_theme_key(value) if key == 'theme_key'
    value
  end

  def validate_theme_key(value)
    return if ALLOWED_THEME_KEYS.include?(value)

    raise ValidationError, "theme_key '#{value}' is not in allowed enum"
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
