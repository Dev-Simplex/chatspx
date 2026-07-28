# frozen_string_literal: true

# Resolve o telefone de um participante de grupo a partir do LID, com cache.
#
# Ordem de tentativa:
#   1. cache Redis (`Whatsapp::LidPhoneCache`) — inclusive o negativo, que evita
#      martelar a WAHA por um LID que ela ja disse nao conhecer;
#   2. `GET /api/{session}/lids/{lid}` (`Waha::ApiService#get_lid_phone_number`);
#   3. `GET /api/{session}/lids` — a lista inteira. Quando cai aqui, aproveita e
#      grava TODO o mapa no cache de uma vez; um unico job paga a chamada e os
#      participantes seguintes acertam direto no passo 1. Protegido por um lock
#      curto no Redis para varios jobs simultaneos nao repetirem a listagem.
#
# Nunca levanta: a resolucao e um enriquecimento, nao pode derrubar quem chama.
class Whatsapp::GroupSenderPhoneResolver
  LIST_LOCK_KEY = 'waha:lid_pn_list_lock'
  LIST_LOCK_TTL = 5.minutes
  LIST_LIMIT = 500
  # Sessao parada (medido: sessao inexistente na WAHA nao devolve 404, estoura os
  # 8s de read timeout). Sem este freio, cada mensagem de um grupo em inbox com
  # sessao morta segura um socket por 8s e ainda reagenda 3x. Mesmo padrao de
  # `Waha::MessageStatusSyncService`.
  CIRCUIT_KEY = 'waha:lid_pn:circuit'
  CIRCUIT_TTL = 60

  def initialize(session_name)
    @session_name = session_name
  end

  # Telefone em digitos (E.164 sem "+") ou nil.
  #
  # Levanta `Waha::ApiService::Error` quando a WAHA esta indisponivel, de proposito:
  # quem chama e o job, que tem backoff. Sessao/LID inexistente NAO levanta — isso
  # e conhecimento estavel e vira cache negativo.
  def phone_for(lid)
    return nil if @session_name.blank? || Whatsapp::LidPhoneCache.normalize_lid(lid).blank?

    cached = Whatsapp::LidPhoneCache.read(@session_name, lid)
    return cached.presence unless cached.nil?
    return nil if circuit_open?

    resolve_and_cache(lid)
  end

  private

  def resolve_and_cache(lid)
    phone = fetch_from_waha(lid)
    if phone.present?
      close_circuit
      Whatsapp::LidPhoneCache.write(@session_name, lid, phone)
    else
      Whatsapp::LidPhoneCache.write_unresolved(@session_name, lid)
    end
    phone.presence
  rescue Waha::ApiService::ConnectionError => e
    # Timeout/conexao: abre o circuito para as proximas mensagens nao pagarem os
    # 8s de novo, e propaga para o job reagendar com backoff.
    open_circuit
    Rails.logger.warn("[GroupSenderPhone] WAHA indisponivel (#{@session_name}); circuito aberto por #{CIRCUIT_TTL}s: #{e.message}")
    raise
  rescue Waha::ApiService::NotFoundError => e
    # Sessao inexistente ou LID desconhecido: cacheia negativo para nao repetir a
    # chamada a cada mensagem do grupo.
    Rails.logger.info("[GroupSenderPhone] WAHA nao conhece lid=#{lid}: #{e.message}")
    Whatsapp::LidPhoneCache.write_unresolved(@session_name, lid)
    nil
  end

  def fetch_from_waha(lid)
    direct = extract_pn(waha_service.get_lid_phone_number(@session_name, jid_for(lid)))
    return direct if direct.present?

    phone_from_list(lid)
  end

  # Fallback caro: puxa a lista e popula o cache inteiro. So um job por vez.
  def phone_from_list(lid)
    return nil unless acquire_list_lock

    list = waha_service.get_lids_list(@session_name, limit: LIST_LIMIT, offset: 0)
    return nil unless list.is_a?(Array)

    Whatsapp::LidPhoneCache.write_many(@session_name, mapping_from(list))
    entry = list.find { |item| same_lid?(item, lid) }
    extract_pn(entry)
  end

  def mapping_from(list)
    list.each_with_object({}) do |item, mapping|
      next unless item.is_a?(Hash)

      entry_lid = item['lid'] || item[:lid]
      pn = extract_pn(item)
      next if entry_lid.blank? || pn.blank?

      mapping[entry_lid] = pn
    end
  end

  def same_lid?(item, lid)
    return false unless item.is_a?(Hash)

    Whatsapp::LidPhoneCache.normalize_lid(item['lid'] || item[:lid]) ==
      Whatsapp::LidPhoneCache.normalize_lid(lid)
  end

  # A WAHA responde 'pn' e, em alguns engines, 'number'.
  def extract_pn(hash)
    return nil unless hash.is_a?(Hash)

    raw = hash['pn'].presence || hash[:pn].presence || hash['number'].presence || hash[:number].presence
    Whatsapp::LidPhoneCache.normalize_phone(raw).presence
  end

  # O endpoint espera o JID completo; o group_sender guarda so os digitos.
  def jid_for(lid)
    digits = Whatsapp::LidPhoneCache.normalize_lid(lid)
    "#{digits}@lid"
  end

  def circuit_open?
    Redis::Alfred.get(circuit_key).present?
  rescue StandardError
    false
  end

  def open_circuit
    Redis::Alfred.setex(circuit_key, '1', CIRCUIT_TTL)
  rescue StandardError => e
    Rails.logger.warn("[GroupSenderPhone] falha ao abrir o circuito: #{e.message}")
  end

  def close_circuit
    Redis::Alfred.delete(circuit_key)
  rescue StandardError
    nil
  end

  def circuit_key
    "#{CIRCUIT_KEY}:#{@session_name}"
  end

  def acquire_list_lock
    Redis::Alfred.set("#{LIST_LOCK_KEY}:#{@session_name}", '1', nx: true, ex: LIST_LOCK_TTL.to_i).present?
  rescue StandardError => e
    Rails.logger.warn("[GroupSenderPhone] lock do fallback de lista falhou: #{e.message}")
    false
  end

  def waha_service
    @waha_service ||= Waha::ApiService.new
  end
end
