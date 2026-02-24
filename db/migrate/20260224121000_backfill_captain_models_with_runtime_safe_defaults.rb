# frozen_string_literal: true

class BackfillCaptainModelsWithRuntimeSafeDefaults < ActiveRecord::Migration[7.0]
  FEATURE_KEYS = %w[
    editor
    assistant
    copilot
    label_suggestion
    audio_transcription
    help_center_search
  ].freeze

  def up
    updated_accounts = 0

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        next unless account.settings.is_a?(Hash)

        current_models = account.settings['captain_models']
        next unless current_models.is_a?(Hash) && current_models.present?

        new_models = current_models.deep_stringify_keys
        changed = false

        FEATURE_KEYS.each do |feature_key|
          configured_model = new_models[feature_key]
          next if configured_model.blank?

          model_is_valid = Llm::Models.valid_model_for?(feature_key, configured_model)
          model_supported = Llm::Models.runtime_supported_model?(configured_model)
          next if model_is_valid && model_supported

          replacement_model = Llm::Models.first_runtime_supported(
            Llm::Models.default_model_for(feature_key),
            Llm::Config::DEFAULT_MODEL
          )

          if replacement_model.present?
            new_models[feature_key] = replacement_model
          else
            new_models.delete(feature_key)
          end

          changed = true
        end

        next unless changed

        new_settings = account.settings.deep_dup
        new_settings['captain_models'] = new_models
        account.update_columns(settings: new_settings, updated_at: Time.current)
        updated_accounts += 1
      end
    end

    say("Backfilled captain_models for #{updated_accounts} account(s)")
  end

  def down
    # Intentionally no-op: the previous values might be invalid for runtime and
    # restoring them could break Captain/Copilot requests again.
  end
end
