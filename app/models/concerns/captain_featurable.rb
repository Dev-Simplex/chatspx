# frozen_string_literal: true

module CaptainFeaturable
  extend ActiveSupport::Concern

  # Features cujo estado REAL nao mora em captain_features: o codigo ja respeita outra
  # chave, gravada por outra tela. A tela de Agentes IA passa a ler e gravar ESSA chave,
  # em vez de manter uma segunda copia que ninguem le. Era o caso da transcricao de audio:
  # o gate de verdade e settings['audio_transcriptions'] (plural), lido em
  # Attachment#schedule_audio_transcription e em Messages::AudioTranscriptionService.
  EXTERNAL_FEATURE_GATES = {
    'audio_transcription' => :audio_transcriptions
  }.freeze

  # Features que hoje rodam SEM gate nenhum, ligadas pra todo mundo. Ao ganharem gate,
  # chave AUSENTE tem que significar LIGADO: com a regra antiga (ausente => false) toda
  # conta que nunca abriu a tela perderia o recurso em silencio no primeiro deploy.
  DEFAULT_ON_FEATURES = %w[label_suggestion].freeze

  included do
    validate :validate_captain_models

    # Dynamically define accessor methods for each captain feature
    Llm::Models.feature_keys.each do |feature_key|
      # Define enabled? methods (e.g., captain_editor_enabled?)
      define_method("captain_#{feature_key}_enabled?") do
        captain_features_with_defaults[feature_key]
      end

      # Define model accessor methods (e.g., captain_editor_model)
      define_method("captain_#{feature_key}_model") do
        captain_models_with_defaults[feature_key]
      end
    end
  end

  # Aplica em cima do que ja existe o payload de features vindo da tela. As features com
  # gate externo sao gravadas na chave que o codigo respeita e REMOVIDAS de captain_features,
  # pra nao sobrar uma copia velha divergindo da verdade.
  def apply_captain_features(incoming_features)
    incoming = (incoming_features || {}).stringify_keys
    merged = (captain_features || {}).merge(incoming)

    EXTERNAL_FEATURE_GATES.each do |feature_key, settings_key|
      merged.delete(feature_key)
      next unless incoming.key?(feature_key)

      public_send(:"#{settings_key}=", ActiveModel::Type::Boolean.new.cast(incoming[feature_key]))
    end

    self.captain_features = merged
  end

  def captain_preferences
    {
      models: captain_models_with_defaults,
      features: captain_features_with_defaults
    }.with_indifferent_access
  end

  private

  def captain_models_with_defaults
    stored_models = captain_models || {}
    Llm::Models.feature_keys.each_with_object({}) do |feature_key, result|
      stored_value = stored_models[feature_key]
      result[feature_key] = if stored_value.present? && Llm::Models.valid_model_for?(feature_key, stored_value)
                              stored_value
                            else
                              Llm::Models.default_model_for(feature_key)
                            end
    end
  end

  def captain_features_with_defaults
    Llm::Models.feature_keys.index_with { |feature_key| captain_feature_enabled?(feature_key) }
  end

  def captain_feature_enabled?(feature_key)
    feature_key = feature_key.to_s
    settings_key = EXTERNAL_FEATURE_GATES[feature_key]
    return external_feature_gate_enabled?(settings_key) if settings_key

    stored_value = (captain_features || {})[feature_key]
    return DEFAULT_ON_FEATURES.include?(feature_key) if stored_value.nil?

    stored_value == true
  end

  def external_feature_gate_enabled?(settings_key)
    ActiveModel::Type::Boolean.new.cast(public_send(settings_key)) == true
  end

  def validate_captain_models
    return if captain_models.blank?

    captain_models.each do |feature_key, model_name|
      next if model_name.blank?
      next if Llm::Models.valid_model_for?(feature_key, model_name)

      allowed_models = Llm::Models.models_for(feature_key)
      errors.add(:captain_models, "'#{model_name}' is not a valid model for #{feature_key}. Allowed: #{allowed_models.join(', ')}")
    end
  end
end
