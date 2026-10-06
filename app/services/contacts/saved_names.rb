# frozen_string_literal: true

# Numero -> nome de quem o salvou na conta. Regra do produto: a partir do momento que um numero esta salvo no
# sistema, toda tela que mostraria so o numero mostra o nome do dono dele (grupo, bolha, card de contato, Kanban...).
#
# O mesmo celular brasileiro existe com e sem o nono digito (o WhatsApp manda +55 66 9657-1379, a ficha guarda
# +55 66 99657-1379): procuramos as duas formas. Havendo duas fichas, vence a que tem nome de verdade.
#
# Entrada: telefones em qualquer formato. Saida: { '556696571379' => { id:, name: } } (chave = digitos como vieram),
# so para quem tem ficha. `name` e nil quando nenhuma ficha tem nome de verdade (ex.: o proprio numero).
module Contacts::SavedNames
  module_function

  def call(account, phones)
    variants = phones.filter_map { |phone| phone.to_s.gsub(/\D/, '').presence }.uniq.index_with { |digits| variants_of(digits) }
    return {} if variants.empty?

    fichas = fichas_by_digits(account, variants.values.flatten)
    variants.each_with_object({}) do |(phone, options), found|
      contact = best_ficha(options.filter_map { |digits| fichas[digits] })
      found[phone] = { id: contact.id, name: real_name(contact.name) } if contact
    end
  end

  def fichas_by_digits(account, digits)
    account.contacts.where(phone_number: digits.map { |value| "+#{value}" })
           .select(:id, :name, :phone_number)
           .index_by { |contact| contact.phone_number.delete('+') }
  end

  # Duas fichas do mesmo numero (com e sem o nono digito): vence a que tem nome de verdade.
  def best_ficha(fichas)
    fichas.find { |ficha| real_name(ficha.name) } || fichas.first
  end

  # Celular BR: 55 + DDD + 8 digitos (sem o 9) <-> 55 + DDD + 9 + 8 digitos. Fixo (comeca com 2-5) nao tem nono digito.
  def variants_of(digits)
    return [digits] unless digits.start_with?('55')

    if digits.length == 12 && digits[4].to_i >= 6
      [digits, "#{digits[0, 4]}9#{digits[4..]}"]
    elsif digits.length == 13 && digits[4] == '9'
      [digits, "#{digits[0, 4]}#{digits[5..]}"]
    else
      [digits]
    end
  end

  # Ficha criada pelo proprio WhatsApp costuma ter o numero como nome: isso nao identifica ninguem.
  def real_name(name)
    name.to_s.strip.presence if name.to_s.match?(/\p{L}/)
  end
end
