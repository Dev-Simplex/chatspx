class JsonbAttributesLengthValidator < ActiveModel::EachValidator
  MAX_STRING_LENGTH = 1500
  MAX_INTEGER_VALUE = 9_999_999_999

  # O teto de tamanho enxergava so String e Integer no TOPO do hash. Valor
  # ANINHADO passava inteiro: {"bag" => {...100 KB}} nao e String nem Integer, e
  # o `case` caia no `else`. Medido pela rota do widget, 10 PATCH desse formato
  # terminavam com 1.014.022 bytes no jsonb do contato, todos com 200.
  #
  # Por isso o teto agora tambem e de BYTES do jsonb serializado e de
  # PROFUNDIDADE — as duas unicas medidas que um valor aninhado nao contorna.
  class << self
    def byte_size(value)
      return 0 if value.blank?

      value.to_json.bytesize
    end

    # Escalar = 0; hash/array = 1 + o mais fundo dos filhos. {"a" => 1} e 1,
    # {"a" => {"b" => 1}} e 2. Array conta como nivel: e mais um degrau de
    # aninhamento que o payload pode usar para esconder tamanho.
    def depth(value)
      case value
      when Hash then 1 + (value.values.map { |nested| depth(nested) }.max || 0)
      when Array then 1 + (value.map { |nested| depth(nested) }.max || 0)
      else 0
      end
    end

    def value_within_limits?(value)
      case value
      when String then value.length <= MAX_STRING_LENGTH
      when Integer then value <= MAX_INTEGER_VALUE
      else true
      end
    end
  end

  def validate_each(record, attribute, value)
    # `blank?` e nao `empty?`: nem todo modelo garante {} antes da validacao.
    return if value.blank?

    @attribute = attribute
    @record = record
    @previous = previous_value

    validate_key_count(value)
    validate_byte_size(value)
    validate_depth(value)
    value.each do |key, attribute_value|
      # Valor que ja estava gravado identico nao e crescimento: recusa-lo
      # travaria a edicao de nome e telefone de todo contato historico, e
      # quebraria a fusao cujo contato base carrega um valor antigo.
      validate_keys(key, attribute_value) unless unchanged?(key, attribute_value)
    end
  end

  def validate_keys(key, attribute_value)
    case attribute_value.class.name
    when 'String'
      @record.errors.add @attribute, "#{key} length should be < #{MAX_STRING_LENGTH}" if attribute_value.length > MAX_STRING_LENGTH
    when 'Integer'
      @record.errors.add @attribute, "#{key} value should be < #{MAX_INTEGER_VALUE}" if attribute_value > MAX_INTEGER_VALUE
    end
  end

  private

  def validate_key_count(value)
    max_keys = options[:max_keys]
    return if max_keys.blank?
    return if value.size <= max_keys
    # Quem ja estourou o teto continua salvando: a validacao morde no
    # CRESCIMENTO, nao no estado. Senao um limite novo travaria a edicao de
    # nome e telefone de todo contato historico que ja passou do numero.
    return if value.size <= @previous.size

    @record.errors.add @attribute, "cannot have more than #{max_keys} attributes (got #{value.size})"
  end

  def validate_byte_size(value)
    max_bytes = options[:max_bytes]
    return if max_bytes.blank?

    size = self.class.byte_size(value)
    return if size <= max_bytes
    return if size <= self.class.byte_size(@previous)

    @record.errors.add @attribute, "total size should be at most #{max_bytes} bytes (got #{size})"
  end

  def validate_depth(value)
    max_depth = options[:max_depth]
    return if max_depth.blank?

    depth = self.class.depth(value)
    return if depth <= max_depth
    return if depth <= self.class.depth(@previous)

    @record.errors.add @attribute, "nesting should be at most #{max_depth} levels deep (got #{depth})"
  end

  def unchanged?(key, attribute_value)
    @previous.key?(key) && @previous[key] == attribute_value
  end

  def previous_value
    return {} unless @record.persisted?
    return {} unless @record.respond_to?("#{@attribute}_was")

    previous = @record.public_send("#{@attribute}_was")
    previous.is_a?(Hash) ? previous : {}
  end
end
