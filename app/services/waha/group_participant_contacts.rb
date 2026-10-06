# frozen_string_literal: true

# Liga cada integrante de um grupo de WhatsApp ao contato SALVO na conta, pelo telefone.
#
# O WhatsApp quase nunca manda o nome do integrante (DisplayName vem vazio), entao a lista do grupo so mostrava
# numeros. Quem o agente ja salvou no ChatSPX tem nome; aqui buscamos esse nome numa consulta so.
#
# O mesmo celular brasileiro aparece com e sem o nono digito (o grupo manda +55 66 9657-1379, a ficha guarda
# +55 66 99657-1379): procuramos as duas formas.
#
# Entrada: telefones em digitos (formato do snapshot C3). Saida: { '556696571379' => { id:, name: } }, so para
# quem tem contato. `name` e nil quando a ficha nao tem nome de verdade (ex.: o proprio numero).
module Waha::GroupParticipantContacts
  module_function

  def call(account, phones)
    variants = phones.compact.uniq.index_with { |phone| variants_of(phone) }
    return {} if variants.empty?

    contacts = account.contacts.where(phone_number: variants.values.flatten.map { |digits| "+#{digits}" })
                      .select(:id, :name, :phone_number)
                      .index_by { |contact| contact.phone_number.delete('+') }

    variants.each_with_object({}) do |(phone, options), found|
      contact = options.filter_map { |digits| contacts[digits] }.first
      found[phone] = { id: contact.id, name: real_name(contact.name) } if contact
    end
  end

  # Celular BR: 55 + DDD + 8 digitos (sem o 9) <-> 55 + DDD + 9 + 8 digitos. Fixo (comeca com 2-5) nao tem nono digito.
  def variants_of(phone)
    digits = phone.to_s.gsub(/\D/, '')
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
