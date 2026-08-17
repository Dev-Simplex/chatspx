module Llm::Models
  CONFIG = YAML.load_file(Rails.root.join('config/llm.yml')).freeze

  class << self
    def providers = CONFIG.fetch('providers')
    def models = CONFIG.fetch('models')
    def features = CONFIG.fetch('features')
    def feature_keys = features.keys

    def feature?(feature)
      features.key?(feature.to_s)
    end

    def default_model_for(feature)
      features.dig(feature.to_s, 'default')
    end

    def models_for(feature)
      features.dig(feature.to_s, 'models') || []
    end

    def valid_model_for?(feature, model_name)
      models_for(feature).include?(model_name.to_s)
    end

    def runtime_supported_model?(model_id)
      return false if model_id.blank?
      return false unless models.key?(model_id.to_s)

      RubyLLM.models.find(runtime_id_for(model_id))
      true
    rescue RubyLLM::ModelNotFoundError, StandardError
      false
    end

    # RubyLLM normaliza o ID das versoes Claude com hifen (ex.: 'claude-sonnet-4-5'),
    # mas o llm.yml mantem o formato com ponto (ex.: 'claude-sonnet-4.5') pra refletir
    # o branding comercial da Anthropic e a UI que o usuario ve. Esse metodo faz a
    # traducao so no caminho do runtime — converte o ultimo \d+\.\d+ da string em
    # \d+-\d+. Funciona pra claude-sonnet-4.5, claude-haiku-4.5, claude-opus-4.5;
    # versoes antigas (ex.: claude-3.5-haiku) ficam intocadas porque o ponto nao
    # esta no final.
    def runtime_id_for(model_id)
      return model_id if model_id.blank?
      return model_id unless model_id.to_s.start_with?('claude-')

      model_id.to_s.sub(/(\d+)\.(\d+)\z/, '\1-\2')
    end

    def first_runtime_supported(*model_ids)
      model_ids
        .flatten
        .compact
        .map(&:to_s)
        .reject(&:blank?)
        .find { |model_id| runtime_supported_model?(model_id) }
    end

    def model_config(model_name)
      models[model_name.to_s]
    end

    def provider_for(model_name)
      model_config(model_name)&.dig('provider')
    end

    def feature_config(feature_key)
      feature = features[feature_key.to_s]
      return nil unless feature

      {
        models: models_for(feature_key).map do |model_name|
          model = model_config(model_name)
          {
            id: model_name,
            display_name: model['display_name'],
            provider: model['provider'],
            coming_soon: model['coming_soon'],
            credit_multiplier: model['credit_multiplier']
          }
        end,
        default: feature['default']
      }
    end
  end
end
