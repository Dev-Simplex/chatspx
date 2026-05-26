# Busca dados completos de um lead na Meta Graph API.
# Webhook traz só leadgen_id; campos reais vem desta chamada.
module Meta
  module LeadAds
    class FetchLeadService
      BASE_URI = 'https://graph.facebook.com'.freeze
      GRAPH_VERSION = 'v22.0'.freeze
      FIELDS = 'id,created_time,ad_id,ad_name,form_id,campaign_id,campaign_name,adset_id,adset_name,field_data,platform'.freeze

      PHONE_KEYS = %w[phone_number phone telefone celular whatsapp].freeze
      NAME_KEYS = %w[full_name name nome nome_completo].freeze
      EMAIL_KEYS = %w[email e-mail].freeze
      CITY_KEYS = %w[city cidade].freeze

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
          acc[f['name'].to_s.downcase] = Array(f['values']).first
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
          full_name: pick(fields, NAME_KEYS),
          phone_number: pick(fields, PHONE_KEYS),
          email: pick(fields, EMAIL_KEYS),
          city: pick(fields, CITY_KEYS),
          raw_fields: fields
        }
      end

      def pick(fields, keys)
        keys.each { |k| return fields[k] if fields[k].present? }
        nil
      end
    end
  end
end
