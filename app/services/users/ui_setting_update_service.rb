# frozen_string_literal: true

# Performs an atomic JSONB merge on `users.ui_settings` so that mobile-only
# preferences (wallpaper, font_scale, theme_preference) coexist with the
# Vue dashboard preferences (conversations_filter_by, display_rich_content_editor, etc.).
#
# The merge is performed via the `||` JSONB operator inside `update_all`, which
# bypasses Rails callbacks and validations to avoid race conditions / overwrites
# when two clients update different keys concurrently.
#
# NOTE: `wallpaper_key` is accepted as a free-form string (up to 64 chars) until
# the canonical PNG asset registry is defined. Validation can be tightened to an
# enum in a follow-up PR once the asset list is frozen.
class Users::UiSettingUpdateService
  ALLOWED_KEYS = %w[wallpaper_key font_scale theme_preference].freeze
  THEME_PREFERENCES = %w[light dark system].freeze
  FONT_SCALE_MIN = 0.85
  FONT_SCALE_MAX = 1.30
  WALLPAPER_KEY_MAX_LENGTH = 64

  attr_reader :errors

  def initialize(user:, params:)
    @user = user
    @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    @errors = []
  end

  def perform
    sanitized = sanitize_params
    return false if @errors.any?
    return true if sanitized.empty?

    User.where(id: @user.id).update_all([
      "ui_settings = coalesce(ui_settings, '{}'::jsonb) || ?::jsonb",
      sanitized.to_json
    ])

    @user.reload
    true
  end

  private

  def sanitize_params
    sanitized = {}

    @params.each do |raw_key, value|
      key = raw_key.to_s
      next unless ALLOWED_KEYS.include?(key)

      case key
      when 'wallpaper_key'
        validated = validate_wallpaper_key(value)
        sanitized[key] = validated unless validated.nil?
      when 'theme_preference'
        validated = validate_theme_preference(value)
        sanitized[key] = validated unless validated.nil?
      when 'font_scale'
        validated = validate_font_scale(value)
        sanitized[key] = validated unless validated.nil?
      end
    end

    sanitized
  end

  def validate_wallpaper_key(value)
    # Allow explicit null to clear the wallpaper.
    return nil if value.nil?

    string_value = value.to_s
    if string_value.length > WALLPAPER_KEY_MAX_LENGTH
      @errors << "wallpaper_key must be at most #{WALLPAPER_KEY_MAX_LENGTH} characters"
      return nil
    end

    string_value
  end

  def validate_theme_preference(value)
    string_value = value.to_s
    unless THEME_PREFERENCES.include?(string_value)
      @errors << "theme_preference must be one of: #{THEME_PREFERENCES.join(', ')}"
      return nil
    end

    string_value
  end

  def validate_font_scale(value)
    float_value = Float(value)
    if float_value < FONT_SCALE_MIN || float_value > FONT_SCALE_MAX
      @errors << "font_scale must be between #{FONT_SCALE_MIN} and #{FONT_SCALE_MAX}"
      return nil
    end

    float_value
  rescue ArgumentError, TypeError
    @errors << 'font_scale must be a numeric value'
    nil
  end
end
