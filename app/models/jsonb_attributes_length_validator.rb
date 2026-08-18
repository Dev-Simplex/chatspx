class JsonbAttributesLengthValidator < ActiveModel::EachValidator
  MAX_STRING_LENGTH = 1500
  MAX_INTEGER_VALUE = 9_999_999_999

  def validate_each(record, attribute, value)
    # `blank?` e nao `empty?`: nem todo modelo garante {} antes da validacao.
    return if value.blank?

    @attribute = attribute
    @record = record

    validate_key_count(value)
    value.each do |key, attribute_value|
      validate_keys(key, attribute_value)
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
    return if value.size <= previous_key_count

    @record.errors.add @attribute, "cannot have more than #{max_keys} attributes (got #{value.size})"
  end

  def previous_key_count
    return 0 unless @record.persisted?
    return 0 unless @record.respond_to?("#{@attribute}_was")

    previous = @record.public_send("#{@attribute}_was")
    previous.is_a?(Hash) ? previous.size : 0
  end
end
