# Explicit grammar cases and typed fact tuple are reviewed together.
# rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
class Captain::Evidence::ClaimExtractor
  VERSION = 'pt-BR-v1'.freeze
  MONEY = /R\$\s*[+-]?\d(?:[\d.,]*\d)?(?:\s*(?:milh(?:ão|ões|oes)|mil))?/i
  PROPERTY_ID = /(?:im[óo]vel|c[óo]d(?:igo)?|ref)\s*[:#.]?\s*(\d+)/i
  LABELS = { /total|somando|aluguel\s*\+\s*condom[íi]nio/i => ['monthly_total', 'BRL/month'],
             /taxa|condom[íi]nio/i => ['condo_fee', 'BRL/month'],
             /venda|comprar/i => %w[sale_price BRL], /aluguel|loca[çc][ãa]o/i => ['rent', 'BRL/month'] }.freeze

  def self.entity_ids(text)
    (text.scan(PROPERTY_ID).flatten + text.scan(%r{/imovel/[^\s/?#]*?-(\d+)(?:[/?#]|\z)}i).flatten).uniq
  end

  def initialize(scope)
    @scope = scope
  end

  def extract(text)
    text.to_s.split(/\n|;|(?<=[.!?])\s+(?=[[:upper:]])/).flat_map do |line|
      ids = self.class.entity_ids(line)
      entity = if ids.size == 1
                 ids.first
               else
                 (ids.empty? ? @scope.entity_id : nil)
               end
      money_claims(line, entity) + boolean_claims(line, entity) + completeness_claims(line) + contact_claims(line)
    end
  end

  private

  def claim(entity, field, type, value, unit, entity_type: 'property', **extra)
    { entity_type: entity_type, entity_id: entity, field: field, value_type: type, value: value, unit: unit,
      assertion_scope: 'business', **extra }
  end

  def money_claims(line, entity)
    line.to_enum(:scan, MONEY).map do
      match = Regexp.last_match
      before = line[0...match.begin(0)]
      quote = quote_scope(line)
      if quote
        claim(@scope.turn_id, 'amount', 'money', match[0], 'BRL', entity_type: 'message', assertion_scope: quote,
                                                                  quote_source_id: @scope.turn_id)
      else
        # Only the closest explicit field label can bind a value. Never use a number elsewhere in the ledger.
        label = LABELS.filter_map do |pattern, (field, unit)|
          positions = before.enum_for(:scan, pattern).map { Regexp.last_match.begin(0) }
          [positions.last, field, unit] if positions.any?
        end.max_by(&:first)
        label = [0, 'monthly_total', 'BRL/month'] if before.match?(/aluguel\s*\+\s*condom[íi]nio\s*[:=]?\s*\z/i)
        if label
          claim(entity, label[1], 'money', match[0], label[2])
        else
          claim(entity, 'price', 'money', match[0], 'BRL')
        end
      end
    end
  end

  def quote_scope(line)
    return 'user_quote' if line.match?(/voc[êe]\s+(?:informou|disse|mencionou)|segundo\s+voc[êe]/i)
    return 'ad_quote' if line.match?(/(?:no|o)\s+an[úu]ncio\s+(?:dizia|mostra|mostrava|informa|informava)|valor\s+do\s+(?:criativo|an[úu]ncio)/i)

    nil
  end

  def boolean_claims(line, entity)
    if line.match?(/(?:fica|est[áa]|[ée]|situado).*?condom[íi]nio\s+fechado/i)
      value = !line.match?(/n[ãa]o\s+(?:fica|est[áa]|[ée])|fora\s+de?\s*condom/i)
      [claim(entity, 'gated_community', 'boolean', value, 'boolean')]
    elsif line.match?(/(?:[ée]|im[óo]vel.*?)\s+avulso|fora\s+de\s+condom[íi]nio/i)
      [claim(entity, 'gated_community', 'boolean', false, 'boolean')]
    else
      []
    end
  end

  def completeness_claims(line)
    all = line.match?(/(?:tod[oa]s.*?(?:op[çc][õo]es|im[óo]veis)|(?:s[ãa]o|essas|estas).*?tod[oa]s)/i)
    none = line.match?(/nenhum[ao]?.*?(?:im[óo]vel|op[çc][ãa]o)|n[ãa]o\s+h[áa]\s+(?:im[óo]veis|op[çc][õo]es)/i)
    all ||= line.match?(/\A\s*tod[oa]s[.!]?\s*\z/i)
    none ||= line.match?(/\A\s*nenhum[ao]?[.!]?\s*\z/i)
    return [] unless all || none

    rows = [claim(@scope.query_id, 'complete', 'boolean', true, 'boolean', entity_type: 'query')]
    rows << claim(@scope.query_id, 'total_count', 'integer', '0', 'count', entity_type: 'query') if none
    rows
  end

  def contact_claims(line)
    rows = []
    if (match = line.match(/telefone\s*[:é]?\s*(\+?[\d\s().-]{8,25})/i))
      rows << claim(@scope.unit_id, 'phone', 'phone', match[1], 'phone', entity_type: 'unit')
    end
    %w[latitude longitude].each do |field|
      match = line.match(/#{field}\s*[:=]?\s*([+-]?\d+(?:[.,]\d+)?)/i)
      rows << claim(@scope.unit_id, field, 'decimal', match[1], 'degree', entity_type: 'unit') if match
    end
    rows
  end
end
# rubocop:enable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
