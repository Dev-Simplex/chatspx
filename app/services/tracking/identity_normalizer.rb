# frozen_string_literal: true

# Bloco 5.11 — T-C5.2 e T-C5.3: normalizacao ANTES do hash, e o hash SEMPRE no servidor.
#
# A ordem nao e detalhe de estilo. SHA-256 de " Alguem@Exemplo.COM " e SHA-256 de
# "alguem@exemplo.com" sao dois digests sem relacao nenhuma: hashear antes de normalizar produz um
# payload aceito pelo destino, com 200 na resposta, que simplesmente nao casa com ninguem. O erro
# nao aparece em log — aparece no EMQ do cliente tres semanas depois.
#
# Por isso a API publica daqui e "hashed_*": quem chama nao consegue escolher a ordem errada.
# `digest` fica exposto so para o spec provar que o valor hasheado e o valor NORMALIZADO.
#
# Duas normalizacoes de telefone, porque os dois destinos pedem coisas diferentes [R07 §2.5, §3.7]:
#   Meta   -> so digitos, com DDI  ("+55 (11) 99999-8888" -> "5511999998888")
#   Google -> E.164, com o "+"     ("+55 (11) 99999-8888" -> "+5511999998888")
module Tracking::IdentityNormalizer
  ACCENT_STRIPPER = ->(value) { value.unicode_normalize(:nfd).gsub(/\p{Mn}/, '') }

  module_function

  # SHA-256 hexadecimal, minusculo. O hash acontece AQUI, no servidor: mandar o valor cru ao
  # navegador para ele hashear seria vazar o dado que o hash existe para proteger (RC10).
  def digest(normalized_value)
    return nil if normalized_value.blank?

    Digest::SHA256.hexdigest(normalized_value)
  end

  def email(value)
    return nil if value.blank?

    normalized = value.to_s.strip.downcase
    normalized.include?('@') ? normalized : nil
  end

  # Meta: so digitos, e o DDI e OBRIGATORIO. Telefone sem codigo de pais nao casa [R07 §2.5], e
  # mandar assim mesmo nao e neutro: entra na conta do EMQ como sinal que nunca bate. Como a unica
  # evidencia confiavel de DDI e o "+" do E.164 (que e o formato que `Contact#phone_number` ja
  # valida), numero sem "+" vira `nil` — nao mandar e melhor que mandar errado.
  def phone_digits(value)
    e164 = phone_e164(value)
    e164&.delete('+')
  end

  # Google: E.164 mesmo, com o "+".
  def phone_e164(value)
    return nil if value.blank?

    candidate = value.to_s.strip.gsub(/[\s()\-.]/, '')
    return nil unless candidate.match?(/\A\+[1-9]\d{1,14}\z/)

    candidate
  end

  # Meta: minusculas, sem pontuacao. Acento fica (a doc aceita UTF-8), porque tirar acento de
  # "Joao"/"Joao" produziria dois valores diferentes dependendo de quem digitou.
  def person_name(value)
    return nil if value.blank?

    normalized = value.to_s.strip.downcase.gsub(/[^[:alpha:]\s]/, '').squeeze(' ').strip
    normalized.presence
  end

  # Cidade: minuscula, sem espaco e sem pontuacao ("Sao Paulo" -> "saopaulo").
  def city(value)
    return nil if value.blank?

    ACCENT_STRIPPER.call(value.to_s.strip.downcase).gsub(/[^a-z]/, '').presence
  end

  # Estado: a sigla de duas letras, minuscula.
  def region(value)
    return nil if value.blank?

    normalized = ACCENT_STRIPPER.call(value.to_s.strip.downcase).gsub(/[^a-z]/, '')
    normalized.length == 2 ? normalized : nil
  end

  # CEP: so digitos.
  def postal_code(value)
    return nil if value.blank?

    value.to_s.gsub(/\D/, '').presence
  end

  # Pais: ISO 3166-1 alpha-2, minusculo.
  def country(value)
    return nil if value.blank?

    normalized = value.to_s.strip.downcase.gsub(/[^a-z]/, '')
    normalized.length == 2 ? normalized : nil
  end

  # `external_id` e id opaco: nao ha o que normalizar alem de tirar espaco. Hasheia igual, porque a
  # Meta espera hash nesse campo — e porque assim o id interno da base nao viaja em claro.
  def external_id(value)
    value.presence&.to_s&.strip
  end

  def hashed_email(value) = digest(email(value))
  def hashed_phone_digits(value) = digest(phone_digits(value))
  def hashed_phone_e164(value) = digest(phone_e164(value))
  def hashed_person_name(value) = digest(person_name(value))
  def hashed_city(value) = digest(city(value))
  def hashed_region(value) = digest(region(value))
  def hashed_postal_code(value) = digest(postal_code(value))
  def hashed_country(value) = digest(country(value))
  def hashed_external_id(value) = digest(external_id(value))
end
