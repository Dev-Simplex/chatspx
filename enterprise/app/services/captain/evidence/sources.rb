# Versioned source schemas keep every required provenance check next to their normalization.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
class Captain::Evidence::Sources
  VERSION = '1'.freeze
  OPEN_CLOSE = %w[open close].freeze
  START_END = %w[start end].freeze
  PROPERTY_FIELDS = {
    'ValorLocacao' => ['rent', 'money', 'BRL/month'], 'ValorVenda' => %w[sale_price money BRL],
    'ValorCondominio' => ['condo_fee', 'money', 'BRL/month'], 'Condominio' => %w[gated_community boolean boolean],
    'Dormitorios' => %w[bedrooms integer count], 'Latitude' => %w[latitude decimal degree],
    'Longitude' => %w[longitude decimal degree], 'Bairro' => %w[neighborhood text text]
  }.freeze

  def self.record(**args)
    scope = Captain::Evidence::Context.scope
    return unless scope

    Captain::Evidence::Ledger.new(scope).record(**args)
  rescue StandardError => e
    scope.unavailable = true if scope
    Captain::Evidence::Telemetry.emit(**(scope&.metadata || {}), publication_path: Captain::Evidence::Context.publication_path,
                                                                 decision: 'would_block', reason: 'ledger_unavailable', error_class: e.class.name)
    Rails.logger.warn("[fact_guard] source_unavailable error=#{e.class.name}")
    nil
  end

  def self.fact(entity_type, id, field, type, value, unit, **extra)
    { entity_type: entity_type, entity_id: id.to_s, field: field, value_type: type, value: value, unit: unit,
      assertion_scope: 'business', **extra }
  end

  def self.property_facts(data)
    id = data.fetch('Codigo').to_s
    aliases = [data['ImoCodigo']].compact.map(&:to_s).reject(&:empty?)
    PROPERTY_FIELDS.filter_map do |key, (field, type, unit)|
      next if data[key].nil? || data[key].to_s.strip.empty?

      value = Captain::Evidence::Normalizer.call(data[key], type)
      fact('property', id, field, type, value, unit, aliases: aliases)
    rescue ArgumentError
      nil # unknown stays unknown; never nil.to_i == 0 or absent boolean == false
    end
  end

  def self.vista(response, filter:, account_bound:, source_version:, origin: 'tool_query', name: 'vista.list')
    scope = Captain::Evidence::Context.scope
    return unless scope

    data = response.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    query_id = Digest::SHA256.hexdigest(JSON.generate(filter.deep_stringify_keys.sort.to_h))
    scope.query_id = query_id if scope.query_id.nil?
    scope.query_id = 'ambiguous' if scope.query_id != query_id
    rows = data.is_a?(Hash) ? data.values.select { |v| v.is_a?(Hash) && v['Codigo'].present? } : []
    rows = [data] if data.is_a?(Hash) && data['Codigo'].present?
    total = data.is_a?(Hash) && data['total'].to_s.match?(/\A\d+\z/) ? data['total'].to_i : nil
    empty_complete = total&.zero? && data.keys.all? { |key| %w[total paginas pagina quantidade].include?(key) }
    valid = response.code.to_i == 200 && account_bound && response.body.to_s.strip.present? && (rows.any? || empty_complete)
    requested = filter['Codigo'] || filter[:Codigo]
    valid &&= rows.all? { |row| row['Codigo'].to_s == requested.to_s } if requested
    facts = valid ? rows.flat_map { |row| property_facts(row) } : []
    if valid
      facts << fact('query', query_id, 'complete', 'boolean', !total.nil? && total == rows.size, 'boolean')
      facts << fact('query', query_id, 'returned_count', 'integer', rows.size.to_s, 'count')
      facts << fact('query', query_id, 'total_count', 'integer', total.to_s, 'count') unless total.nil?
    end
    record(origin: origin, name: name, version: source_version, status: valid ? 'success' : 'unverified',
           result: { http_status: response.code, body: response.body, data: data, filter: filter }, facts: facts)
  rescue StandardError => e
    record(origin: origin, name: name, version: VERSION, status: 'error',
           result: { http_status: response.code, body: response.body, error_class: e.class.name })
  end

  def self.unit(unit, name: 'unit.read')
    scope = Captain::Evidence::Context.scope
    return unless scope && unit && unit.account_id == scope.account_id

    values = unit.attributes.slice('id', 'name', 'address', 'phone', 'latitude', 'longitude', 'timezone', 'updated_at')
    values['working_hours'] = unit.working_hours.map(&:attributes)
    mapping = { 'address' => %w[text text], 'phone' => %w[phone phone], 'latitude' => %w[decimal degree],
                'longitude' => %w[decimal degree], 'name' => %w[text text] }
    facts = mapping.filter_map do |field, (type, measure)|
      next if values[field].nil? || values[field].to_s.empty?

      fact('unit', unit.id, field, type, values[field], measure)
    end
    values['working_hours'].each do |hours|
      next if hours['closed_all_day']

      OPEN_CLOSE.each do |kind|
        hour = hours["#{kind}_hour"]
        minute = hours["#{kind}_minutes"]
        next if hour.nil? || minute.nil?

        value = format('%<hour>02d:%<minute>02d', hour: hour, minute: minute)
        facts << fact('unit', unit.id, "#{kind}_at:#{hours['day_of_week']}", 'time', value, unit.timezone)
      end
    end
    scope.unit_id = unit.id.to_s if scope.unit_id.nil?
    scope.unit_id = 'ambiguous' if scope.unit_id != unit.id.to_s
    record(origin: 'unit_record', name: name, version: Digest::SHA256.hexdigest(values.to_json), status: 'success',
           result: values, facts: facts)
  rescue StandardError => e
    record(origin: 'unit_record', name: name, version: VERSION, status: 'error', result: { error_class: e.class.name })
  end

  def self.quotes(message)
    scope = Captain::Evidence::Context.scope
    return unless scope && message&.incoming? && message.account_id == scope.account_id

    [['user_report', 'user_quote', message.content.to_s],
     ['ad_creative', 'ad_quote',
      (message.content_attributes['referral'] || {}).slice('headline', 'body').values.join(' ')]].each do |origin, kind, text|
      facts = text.scan(Captain::Evidence::ClaimExtractor::MONEY).map do |value|
        fact('message', message.id, 'amount', 'money', value, 'BRL', assertion_scope: kind)
      end
      next if facts.empty?

      record(origin: origin, name: 'message.quote', version: message.updated_at.iso8601(6), status: 'success',
             result: { message_id: message.id, text: text }, facts: facts)
    end
  rescue StandardError => e
    record(origin: 'user_report', name: 'message.quote', version: VERSION, status: 'error', result: { error_class: e.class.name })
  end

  def self.assistant_hours(assistant, hours, inside)
    scope = Captain::Evidence::Context.scope
    return unless scope && assistant.account_id == scope.account_id

    facts = [fact('assistant', assistant.id, 'inside_business_hours', 'boolean', inside, 'boolean')]
    Array(hours['schedule']).each do |day|
      Array(day['ranges']).each_with_index do |range, index|
        START_END.each do |kind|
          next if range[kind].blank?

          facts << fact('assistant', assistant.id, "#{kind}_at:#{day['day']}:#{index}", 'time', range[kind], hours['timezone'].to_s)
        end
      end
    end
    record(origin: 'assistant_record', name: 'assistant.business_hours', version: assistant.updated_at.iso8601(6),
           status: 'success', result: { hours: hours, inside: inside }, facts: facts)
  rescue StandardError => e
    record(origin: 'assistant_record', name: 'assistant.business_hours', version: VERSION, status: 'error',
           result: { error_class: e.class.name })
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
