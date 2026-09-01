# frozen_string_literal: true

# Normaliza a lista de participantes de um grupo da WAHA para o shape unico que o
# resto do sistema consome (contrato C3 de `conversation.additional_attributes`).
#
# A WAHA devolve DOIS formatos diferentes para o mesmo dado, e nos consumimos os
# dois — por isso a normalizacao mora num lugar so:
#
#   1) shape "engine" (GET /api/{session}/groups -> Participants[], e tambem
#      GET .../participants):
#        {"JID"=>"229480102662169@lid", "PhoneNumber"=>"556699949191@s.whatsapp.net",
#         "LID"=>"229480102662169@lid", "IsAdmin"=>true, "IsSuperAdmin"=>false,
#         "DisplayName"=>"", "Error"=>0, "AddRequest"=>nil}
#
#   2) shape "v2" (GET .../participants/v2):
#        {"id"=>"229480102662169@lid", "pn"=>"556699949191@c.us", "role"=>"admin"}
#
# Saida (sempre com as 4 chaves presentes, `nil` quando desconhecido):
#   {'lid' => '229480102662169', 'phone' => '556699949191',
#    'name' => nil, 'admin' => true}
#
# `lid` e `phone` sao SO DIGITOS (E.164 sem '+'), do mesmo jeito que o C2 define
# `content_attributes.group_sender.phone` e que o helper de front `formatPhone`
# espera. A normalizacao acontece UMA vez, aqui.
module Waha::GroupParticipantsParser
  LID_SUFFIX = '@lid'
  ADMIN_ROLES = %w[admin superadmin].freeze

  module_function

  # raw: Array de Hash em qualquer um dos dois shapes (aceita tambem o objeto de
  # grupo inteiro, de onde extrai `Participants`). Devolve Array de Hash no C3.
  def parse(raw)
    participants(raw).filter_map { |item| normalize(item) }
  end

  # Pares [lid, phone] prontos para o cache Redis LID->PN. So devolve o par
  # quando os DOIS lados existem — cache com valor vazio e pior que cache vazio.
  def lid_pn_pairs(raw)
    parse(raw).filter_map do |p|
      next if p['lid'].blank? || p['phone'].blank?

      [p['lid'], p['phone']]
    end
  end

  # Aceita: Array de participantes, Hash de grupo (com 'Participants'), Array de
  # grupos, ou nil. Qualquer outra coisa vira lista vazia — nunca levanta.
  def participants(raw)
    case raw
    when Array then participants_from_array(raw)
    when Hash then group_like?(raw) ? Array(raw['Participants']) : [raw]
    else []
    end
  end

  def participants_from_array(raw)
    return raw.flat_map { |item| participants(item) } if raw.any? { |item| group_like?(item) }

    raw.select { |item| item.is_a?(Hash) }
  end

  def group_like?(item)
    item.is_a?(Hash) && item.key?('Participants')
  end

  def normalize(item)
    return nil unless item.is_a?(Hash)

    lid = extract_lid(item)
    phone = extract_phone(item)
    return nil if lid.blank? && phone.blank?

    {
      'lid' => lid,
      'phone' => phone,
      'name' => item['DisplayName'].presence || item['name'].presence,
      'admin' => admin?(item)
    }
  end

  # O LID pode chegar em 'LID' (shape engine), no proprio 'JID' quando o grupo usa
  # AddressingMode=lid (100% dos 78 grupos medidos aqui), ou em 'id' (shape v2).
  # Se o participante for enderecado por telefone (@s.whatsapp.net/@c.us) nao ha
  # LID — devolvemos nil em vez de inventar um a partir do telefone.
  def extract_lid(item)
    candidate = [item['LID'], item['JID'], item['id']].find { |value| value.to_s.end_with?(LID_SUFFIX) }
    digits(candidate)
  end

  def extract_phone(item)
    candidate = [item['PhoneNumber'], item['pn']].find(&:present?)
    # Sem PhoneNumber, um JID que NAO e @lid ja e o proprio telefone.
    candidate ||= [item['JID'], item['id']].find { |value| value.present? && !value.to_s.end_with?(LID_SUFFIX) }
    digits(candidate)
  end

  def admin?(item)
    return ADMIN_ROLES.include?(item['role'].to_s.downcase) if item.key?('role')

    item['IsAdmin'] == true || item['IsSuperAdmin'] == true
  end

  # '556699949191@s.whatsapp.net' -> '556699949191' · '+55 66 9994-9191' -> '556699949191'
  # Devolve nil para vazio, 'null', ou qualquer coisa sem digito.
  def digits(value)
    return nil if value.blank?

    stripped = value.to_s.split('@').first.to_s.gsub(/\D/, '')
    stripped.presence
  end
end
