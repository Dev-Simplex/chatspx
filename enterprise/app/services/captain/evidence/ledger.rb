# The source identity requires explicit named fields; no opaque options hash.
# rubocop:disable Metrics/ParameterLists
class Captain::Evidence::Ledger
  class Unavailable < StandardError; end

  def initialize(scope)
    @scope = scope
  end

  def record(origin:, name:, version:, status:, result:, facts: [], observed_at: Time.current, expires_at: nil)
    raise Unavailable, 'episode unavailable' if @scope.unavailable

    payload = result.as_json
    # Savepoint prevents a shadow write error from aborting Message's enclosing transaction.
    Captain::EvidenceSource.transaction(requires_new: true) do
      source = Captain::EvidenceSource.create!(
        **@scope.metadata, origin: origin, source_name: name, source_version: version, status: status,
                           full_result: payload, digest: Digest::SHA256.hexdigest(JSON.generate(payload)), observed_at: observed_at,
                           expires_at: expires_at || @scope.expiry(origin, observed_at), created_at: Time.current
      )
      rows = status == 'success' ? facts.map { |fact| @scope.identity.merge(normalize_fact(fact)) } : []
      # Values normalized above; tenant/source identity and required columns enforced by database constraints.
      source.facts.insert_all!(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
      source
    end
  rescue StandardError => e
    @scope.unavailable = true
    raise Unavailable, e.class.name
  end

  def snapshot(now: Time.current)
    raise Unavailable, 'ledger unavailable' if @scope.unavailable

    sources = Captain::EvidenceSource.select(:id, :origin, :observed_at, :source_name, :source_version)
                                     .where(@scope.identity).where(status: 'success')
                                     .where('observed_at <= ?', now)
                                     .where('(expires_at > ?) OR (expires_at IS NULL AND run_id = ?)', now, @scope.run_id)
    sources.includes(:facts).flat_map do |source|
      source.facts.map do |fact|
        fact.attributes.symbolize_keys.merge(origin: source.origin, observed_at: source.observed_at,
                                             source_name: source.source_name, source_version: source.source_version)
      end
    end
  rescue StandardError => e
    raise Unavailable, e.class.name
  end

  private

  def normalize_fact(fact)
    fact.merge(entity_id: fact.fetch(:entity_id).to_s, aliases: Array(fact[:aliases]).map(&:to_s),
               value: Captain::Evidence::Normalizer.call(fact.fetch(:value), fact.fetch(:value_type)))
  end
end
# rubocop:enable Metrics/ParameterLists
