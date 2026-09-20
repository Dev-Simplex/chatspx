# Keep ordered rejection conditions and proof requirements visible in the same decision table.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class Captain::Evidence::FactGuard
  FIELD_ALIASES = { 'ValorLocacao' => 'rent', 'ValorVenda' => 'sale_price', 'ValorCondominio' => 'condo_fee',
                    'Condominio' => 'gated_community', 'latitude' => 'latitude', 'longitude' => 'longitude' }.freeze
  BUSINESS_ORIGINS = {
    'property' => %w[tool_query property_ref], 'query' => %w[tool_query property_ref],
    'unit' => ['unit_record'], 'assistant' => ['assistant_record']
  }.freeze

  def initialize(ledger)
    @ledger = ledger
  end

  def evaluate(claims)
    facts = @ledger.snapshot
    claims.map { |claim| verify(claim, facts) }
  rescue StandardError
    (claims.presence || [{ field: 'coverage' }]).map { |claim| verdict(claim, 'would_block', 'ledger_unavailable') }
  end

  private

  def verify(claim, facts)
    return verdict(claim, 'unassessed', claim[:unassessed]) if claim[:unassessed]
    return verdict(claim, 'would_allow', 'renderer_generated') if presentation_index?(claim)
    return verdict(claim, 'would_block', 'entity_missing') if claim[:entity_id].to_s.empty?

    field = FIELD_ALIASES.fetch(claim[:field], claim[:field])
    candidates = facts.select { |fact| same_entity?(fact, claim) && permitted_origin?(fact, claim) }
    return verdict(claim, 'would_block', 'ambiguous_alias') if candidates.pluck(:entity_id).uniq.size > 1

    selected = candidates.select { |f| f[:field] == field && f[:unit] == claim[:unit] && f[:value_type] == claim[:value_type] }
    selected = latest(selected)
    expected = Captain::Evidence::Normalizer.call(claim[:value], claim[:value_type])
    return rounded(claim, selected, expected) if claim[:rounding] && selected.any?

    if selected.any?
      return verdict(claim, 'would_block', 'conflicting_sources') if selected.pluck(:value).uniq.size > 1
      return verdict(claim, 'would_allow', 'matched', selected.pluck(:id)) if selected.first[:value] == expected
    end
    derived = derive(claim.merge(field: field), candidates, expected)
    return derived if derived

    verdict(claim, 'would_block', selected.empty? ? 'missing_evidence' : 'contradiction')
  rescue ArgumentError
    verdict(claim, 'would_block', 'invalid_value')
  end

  def same_entity?(fact, claim)
    fact[:entity_type] == claim[:entity_type] &&
      ([fact[:entity_id]] + Array(fact[:aliases])).include?(claim[:entity_id].to_s)
  end

  def permitted_origin?(fact, claim)
    scope = claim.fetch(:assertion_scope, 'business')
    return false unless fact[:assertion_scope] == scope

    case scope
    when 'business' then BUSINESS_ORIGINS.fetch(claim[:entity_type], []).include?(fact[:origin])
    when 'user_quote' then fact[:origin] == 'user_report' && claim[:quote_source_id].to_s == fact[:entity_id]
    when 'ad_quote' then fact[:origin] == 'ad_creative' && claim[:quote_source_id].to_s == fact[:entity_id]
    else false
    end
  end

  def latest(facts)
    return [] if facts.empty?

    at = facts.pluck(:observed_at).max
    facts.select { |f| f[:observed_at] == at }
  end

  def derive(claim, candidates, expected)
    return unless claim[:field] == 'monthly_total' && claim[:value_type] == 'money' && claim[:unit] == 'BRL/month'

    operands = %w[rent condo_fee].map do |field|
      rows = latest(candidates.select { |f| f[:field] == field && f[:unit] == 'BRL/month' && f[:value_type] == 'money' })
      return nil if rows.empty? || rows.map { |f| f[:value] }.uniq.size != 1

      rows.first
    end
    total = operands.sum(BigDecimal(0)) { |f| BigDecimal(f[:value]) }.to_s('F')
    return verdict(claim, 'would_block', 'derivation_mismatch') unless total == expected

    verdict(claim, 'would_allow', 'derived_sum', operands.pluck(:id))
  end

  # Explicit deterministic transformation, never a floating price tolerance.
  def rounded(claim, selected, expected)
    policy = claim[:rounding]
    return verdict(claim, 'would_block', 'invalid_rounding') unless
      policy == { digits: 0, mode: 'half_up' } && claim[:value_type] == 'money'
    return verdict(claim, 'would_block', 'conflicting_sources') unless selected.pluck(:value).uniq.size == 1

    actual = BigDecimal(selected.first[:value]).round(0, BigDecimal::ROUND_HALF_UP).to_s('F')
    verdict(claim, actual == expected ? 'would_allow' : 'would_block', 'derived_round', selected.pluck(:id))
  end

  def verdict(claim, decision, reason, ids = [])
    { fact_type: claim[:field], decision: decision, reason: reason, evidence_ids: ids, claim: claim }
  end

  def presentation_index?(claim)
    claim[:assertion_scope] == 'presentation' && claim[:renderer_generated] &&
      %w[list_index card_index].include?(claim[:field]) && claim[:value_type] == 'integer' && claim[:unit] == 'index'
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
