# Busca dados completos de um lead na Meta Graph API.
# Webhook traz só leadgen_id; campos reais vem desta chamada.
module Meta
  module LeadAds
    class FetchLeadService
      BASE_URI = 'https://graph.facebook.com'.freeze
      GRAPH_VERSION = 'v22.0'.freeze
      FIELDS = 'id,created_time,ad_id,ad_name,form_id,campaign_id,campaign_name,adset_id,adset_name,field_data,platform'.freeze

      # Substrings que identificam o tipo do campo. Match parcial — funciona
      # com qualquer form (nomes custom tipo "qual_seu_telefone?", "celular_contato", etc).
      PHONE_HINTS = %w[phone telefone celular whatsapp numero_de_telefone numero_telefone].freeze
      NAME_HINTS = %w[full_name nome name].freeze
      EMAIL_HINTS = %w[email e-mail mail].freeze
      CITY_HINTS = %w[city cidade].freeze

      # Filtra dummy data do Lead Ads Testing Tool (`<test lead: dummy data for X>`)
      TEST_DUMMY_REGEX = /\A\s*<test lead:.*?>\s*\z/i.freeze

      def initialize(leadgen_id:, access_token:)
        @leadgen_id = leadgen_id
        @access_token = access_token
      end

      def perform
        response = HTTParty.get(
          "#{BASE_URI}/#{GRAPH_VERSION}/#{@leadgen_id}",
          query: { access_token: @access_token, fields: FIELDS }
        )

        raise "Meta Graph API error #{response.code}: #{response.body}" unless response.success?

        parse(response.parsed_response)
      end

      private

      def parse(json)
        fields = (json['field_data'] || []).each_with_object({}) do |f, acc|
          key = normalize_key(f['name'])
          value = Array(f['values']).first
          # Filtra dummy data de Test Tool — preserva chave pra raw_fields mas com nil
          value = nil if value.to_s.match?(TEST_DUMMY_REGEX)
          acc[key] = value
        end

        {
          leadgen_id: json['id'],
          created_time: json['created_time'],
          ad_id: json['ad_id'],
          ad_name: json['ad_name'],
          adset_id: json['adset_id'],
          adset_name: json['adset_name'],
          form_id: json['form_id'],
          campaign_id: json['campaign_id'],
          campaign_name: json['campaign_name'],
          platform: json['platform'],
          full_name: find_by_hints(fields, NAME_HINTS),
          phone_number: find_by_hints(fields, PHONE_HINTS),
          email: find_by_hints(fields, EMAIL_HINTS),
          city: find_by_hints(fields, CITY_HINTS),
          raw_fields: fields
        }
      end

      # Normaliza: lowercase, remove ? e caracteres especiais, normaliza acentos
      def normalize_key(name)
        s = name.to_s.downcase
        s = s.tr("áàâãäéèêëíìîïóòôõöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
        s.gsub(/[^a-z0-9_]/, "_")
      end

      # Match por substring: campo "qual_seu_telefone_" casa com hint "telefone"
      def find_by_hints(fields, hints)
        fields.each do |key, value|
          next if value.blank?
          return value if hints.any? { |h| key.include?(h) }
        end
        nil
      end
    end
  end
end
