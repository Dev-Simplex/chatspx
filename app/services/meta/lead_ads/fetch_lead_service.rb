# Busca dados completos de um lead na Meta Graph API.
# Webhook traz só leadgen_id; campos reais vem desta chamada.
module Meta
  module LeadAds
    class FetchLeadService
      BASE_URI = 'https://graph.facebook.com'.freeze
      GRAPH_VERSION = 'v22.0'.freeze
      # retailer_item_id: em campanhas de catálogo (dynamic ads), é o produto que o lead viu —
      # no caso da Tozi, o CÓDIGO do imóvel no Vista. Permite abrir já no imóvel específico.
      FIELDS = 'id,created_time,ad_id,ad_name,form_id,campaign_id,campaign_name,adset_id,adset_name,field_data,platform,retailer_item_id'.freeze

      # Substrings que identificam o tipo do campo. Match parcial — funciona
      # com qualquer form (nomes custom tipo "qual_seu_telefone?", "celular_contato", etc).
      PHONE_HINTS = %w[phone telefone celular whatsapp numero_de_telefone numero_telefone].freeze
      NAME_HINTS = %w[full_name nome name].freeze
      EMAIL_HINTS = %w[email e-mail mail].freeze
      CITY_HINTS = %w[city cidade].freeze

      # Filtra dummy data do Lead Ads Testing Tool (`<test lead: dummy data for X>`)
      TEST_DUMMY_REGEX = /\A\s*<test lead:.*?>\s*\z/i.freeze

      # A Meta às vezes cola o texto do botão/CTA do anúncio no valor cru do campo nome,
      # separado por 2+ espaços: "Quero saber mais   Tiago". Como o nome vira o contato e o
      # first_name do template, isso faz a IA chamar o lead de "Quero". Estas são as frases de
      # CTA/intenção a descartar quando aparecem como segmento separado (nunca um nome real).
      CTA_PHRASES = [
        'quero saber mais', 'quero saber', 'quero sim', 'sim quero', 'quero',
        'tenho interesse', 'me interessei', 'saiba mais', 'me chama', 'me chama depois',
        'gostaria de saber', 'mais informacoes', 'solicitar informacoes', 'receber contato'
      ].freeze

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
          retailer_item_id: json['retailer_item_id'],
          full_name: sanitize_name(find_by_hints(fields, NAME_HINTS)),
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

      # Limpa o CTA que a Meta às vezes gruda no campo nome ("Quero saber mais   Tiago").
      # Quebra em segmentos separados por 2+ espaços e descarta os que são frase de CTA;
      # sobra o nome real. Se TUDO parecer CTA (lead sem nome de verdade), não apaga —
      # devolve o valor colapsado pro humano tratar. Nome normal passa intacto.
      def sanitize_name(raw)
        return raw if raw.blank?

        segments = raw.to_s.split(/\s{2,}/).map(&:strip).reject(&:blank?)
        cleaned = segments.reject { |seg| cta_phrase?(seg) }
        cleaned = segments if cleaned.empty?
        cleaned.join(' ').gsub(/\s+/, ' ').strip.presence
      end

      def cta_phrase?(segment)
        normalized = segment.to_s.downcase
                            .tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
                            .strip
        CTA_PHRASES.include?(normalized)
      end
    end
  end
end
