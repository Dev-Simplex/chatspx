# frozen_string_literal: true

# Campos personalizados do item do catálogo: um conjunto por conta, definido em
# `CustomAttributeDefinition` com `attribute_model: catalog_attribute`.
#
# É o ÚNICO ponto que converte valor para guardar e que formata valor para mostrar. Painel, porta
# do ERP, planilha, legenda do WhatsApp e bolha passam todos por aqui — formatar em cada um faria
# "R$ 2.500,50" sair de um jeito na mensagem e de outro na tela.
class Catalog::CustomFields
  VERDADEIROS = %w[1 sim s true t yes y verdadeiro on].freeze
  FALSOS = %w[0 nao não n false f no falso off].freeze

  def initialize(account)
    @account = account
  end

  # Na ordem de criação: é a ordem em que os campos aparecem no formulário, no card e na mensagem.
  def definicoes
    @definicoes ||= @account.custom_attribute_definitions.catalog_attribute.order(:id).to_a
  end

  # Devolve só chaves com definição na conta, com o valor já no tipo do campo. Valor em branco sai
  # do resultado (é como se apaga um campo). Valor que não converte levanta erro dizendo o campo.
  def normalizar(valores)
    valores = valores.to_h.stringify_keys
    definicoes.each_with_object({}) do |definicao, resultado|
      valor = valores[definicao.attribute_key]
      next if em_branco?(valor)

      resultado[definicao.attribute_key] = converter(definicao, valor)
    end
  end

  # `[{ label, value }]` pronto para mostrar ao cliente: pula campo interno (`hidden`) e valor vazio.
  def para_exibir(valores)
    valores = valores.to_h
    definicoes.filter_map do |definicao|
      next if definicao.hidden

      texto = formatar(definicao, valores[definicao.attribute_key])
      { 'label' => definicao.attribute_display_name, 'value' => texto } if texto.present?
    end
  end

  private

  # `false` é valor (caixa desmarcada), não ausência — por isso não serve o `blank?`.
  def em_branco?(valor)
    valor.nil? || (valor.is_a?(String) && valor.strip.empty?)
  end

  def converter(definicao, valor)
    invalido!(definicao) if valor.is_a?(Hash) || valor.is_a?(Array)

    case definicao.attribute_display_type
    when 'number', 'currency' then numero(definicao, valor)
    when 'date' then data(definicao, valor)
    when 'checkbox' then booleano(definicao, valor)
    when 'list' then opcao(definicao, valor)
    else valor.to_s.strip
    end
  end

  # "1.234,56" (como o brasileiro digita) e "1234.56" viram o mesmo número: com os dois
  # separadores o ponto é milhar; com um só, ele é decimal. Inteiro fica inteiro, para "3" e 3
  # não contarem como mudança.
  def numero(definicao, valor)
    return inteiro_se_der(valor) if valor.is_a?(Numeric)

    texto = valor.to_s.strip.gsub(/[^\d,.-]/, '')
    texto = texto.include?(',') ? texto.delete('.').tr(',', '.') : texto
    invalido!(definicao) unless texto.match?(/\A-?\d+(\.\d+)?\z/)

    inteiro_se_der(texto.to_f)
  end

  def inteiro_se_der(numero)
    (numero % 1).zero? ? numero.to_i : numero.to_f
  end

  def data(definicao, valor)
    texto = valor.to_s.strip
    formato = texto.include?('/') ? '%d/%m/%Y' : '%Y-%m-%d'
    Date.strptime(texto, formato).iso8601
  rescue Date::Error
    invalido!(definicao)
  end

  def booleano(definicao, valor)
    return valor if [true, false].include?(valor)

    texto = valor.to_s.strip.downcase
    return true if VERDADEIROS.include?(texto)
    return false if FALSOS.include?(texto)

    invalido!(definicao)
  end

  def opcao(definicao, valor)
    texto = valor.to_s.strip
    invalido!(definicao) unless Array(definicao.attribute_values).map(&:to_s).include?(texto)

    texto
  end

  def invalido!(definicao)
    raise CustomExceptions::Catalog::InvalidCustomField.new(field: definicao.attribute_display_name)
  end

  def formatar(definicao, valor)
    return nil if em_branco?(valor)

    case definicao.attribute_display_type
    when 'currency' then "R$ #{milhar(format('%.2f', valor.to_f).tr('.', ','))}"
    when 'number' then numero_br(valor)
    when 'date' then data_br(valor)
    when 'checkbox' then (I18n.t('catalog.custom_fields.checked') if valor == true)
    else valor.to_s
    end
  end

  # Inteiro sai sem casas ("3", não "3.0"); decimal sai com vírgula.
  def numero_br(valor)
    (valor.to_f % 1).zero? ? valor.to_i.to_s : valor.to_s.tr('.', ',')
  end

  def milhar(texto)
    inteiro, decimais = texto.split(',')
    "#{inteiro.reverse.scan(/\d{1,3}/).join('.').reverse},#{decimais}"
  end

  def data_br(valor)
    Date.iso8601(valor.to_s).strftime('%d/%m/%Y')
  rescue Date::Error
    valor.to_s
  end
end
