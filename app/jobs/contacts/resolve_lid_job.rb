# frozen_string_literal: true

class Contacts::ResolveLidJob < ApplicationJob
  queue_as :high
  # Backoff agressivo: 5s, 15s, 30s, 60s, 120s, 300s, 600s (~18min total)
  retry_on Waha::ApiService::Error, wait: ->(executions) { [5, 15, 30, 60, 120, 300, 600][executions - 1] || 600 }, attempts: 7

  def perform(contact_inbox_id)
    contact_inbox = ContactInbox.find_by(id: contact_inbox_id)
    return if contact_inbox.blank?

    contact = contact_inbox.contact
    # Roda se o contact_inbox ainda tem LID OU se o proprio contato ainda
    # carrega name/identifier com @lid (caso em que o contact_inbox ja foi
    # parcialmente normalizado mas o contato ficou com lixo residual).
    return unless needs_resolution?(contact_inbox, contact)

    inbox = contact_inbox.inbox
    session_name = inbox.waha_session_name
    return if session_name.blank?

    lid = lid_for(contact_inbox, contact)
    pn = resolve_pn(session_name, contact, lid)
    return handle_unresolved(session_name, lid, contact_inbox_id) if pn.blank?

    remember_success(session_name, lid, pn)
    normalized_phone = normalize_phone(pn)
    merge_or_update(inbox, contact_inbox, pn, normalized_phone)

    # Notificar frontend via ActionCable que o contato foi atualizado
    broadcast_contact_update(contact_inbox, inbox)
  end

  private

  # Ordem: o mais barato e confiavel primeiro.
  #   1. JID que o proprio webhook ja trouxe (zero I/O);
  #   2. cache Redis LID->PN, populado a cada 30 min pelo Waha::RefreshGroupsJob;
  #   3. WAHA — e so aqui, atras da guarda de sessao/backoff.
  def resolve_pn(session_name, contact, lid)
    pn = pn_from_custom_attributes(contact) || pn_from_cache(session_name, lid)
    return pn if pn.present?
    return nil unless attempt_waha?(session_name, lid)

    resolve_lid_via_waha(session_name, lid)
  end

  def needs_resolution?(contact_inbox, contact)
    contact_inbox.source_id.to_s.end_with?('@lid') ||
      contact.identifier.to_s.end_with?('@lid') ||
      contact.name.to_s.end_with?('@lid')
  end

  def lid_for(contact_inbox, contact)
    contact_inbox.source_id.to_s.end_with?('@lid') ? contact_inbox.source_id : contact.identifier
  end

  # Se o webhook ja trouxe o JID em custom_attributes, evita rodar round-trip
  # no WAHA e resolve inline.
  def pn_from_custom_attributes(contact)
    jid = contact.custom_attributes['waha_whatsapp_jid'].to_s
    return nil unless jid.end_with?('@c.us')

    jid
  end

  # Cache-first. O `Waha::RefreshGroupsJob` ja mantem o mapa LID->PN quente
  # (waha:lid_pn:{sessao}:{lid}, TTL 7d); um acerto aqui poupa um round-trip que
  # custa ate 8s de socket.
  #
  # ⚠️ O cache guarda SO DIGITOS, mas o resto deste job trata `pn` como JID: ele
  # vira `source_id` do contact_inbox (`...@c.us`), que e a chave de identidade do
  # contato. Reconstruir o JID aqui e obrigatorio — devolver digitos crus mudaria
  # silenciosamente essa chave (armadilha documentada em plano/glitchtip/G3).
  def pn_from_cache(session_name, lid)
    return nil if lid.blank?

    digits = Whatsapp::LidPhoneCache.phone(session_name, lid)
    return nil if digits.blank?

    "#{digits}@c.us"
  end

  # Vale a pena gastar a chamada? Dois freios, ambos verificados antes do socket:
  #   - sessao que nao esta WORKING NAO devolve erro rapido: a WAHA leva ~10s para
  #     dizer 422 e o timeout do ApiService e 8s, entao vira Net::ReadTimeout
  #     sempre (causa dos 2.812 eventos da issue 27);
  #   - LID em backoff/negativo: ja falhou e nao mudou nada desde entao.
  # Quando pulamos, `@waha_skipped` marca que NAO houve tentativa — o job termina
  # em silencio, sem levantar e sem queimar as 7 tentativas do retry_on.
  def attempt_waha?(session_name, lid)
    return false if lid.blank?

    return skip_waha("sessao #{session_name} nao esta WORKING") unless Waha::SessionStatusCache.usable?(session_name)
    return skip_waha("LID #{lid} em backoff (falhas=#{Whatsapp::LidPhoneCache.failure_count(session_name, lid)})") if
      Whatsapp::LidPhoneCache.cooling_down?(session_name, lid)
    return skip_waha("LID #{lid} marcado como nao resolvivel ha pouco") if Whatsapp::LidPhoneCache.unresolved?(session_name, lid)

    true
  end

  def skip_waha(reason)
    @waha_skipped = true
    Rails.logger.info("[ResolveLidJob] pulando WAHA: #{reason}")
    false
  end

  def resolve_lid_via_waha(session_name, lid)
    resolve_lid(Waha::ApiService.new, session_name, lid)
  rescue Waha::ApiService::ConnectionError
    # Timeout/conexao: conta como ciclo falho para o proximo sweep respeitar o
    # backoff, e propaga para o retry_on deste job continuar valendo.
    record_failure_once(session_name, lid)
    raise
  end

  # Nao resolveu. Tres situacoes bem diferentes:
  #   - nao chegamos a tentar (guarda de sessao/backoff): nada a registrar, nada a
  #     retentar — retorna em silencio. E o que quebra o loop da issue 27;
  #   - LID degenerado/vazio: idem;
  #   - tentamos e a WAHA nao soube: registra o ciclo falho, marca o negativo curto
  #     e levanta para o retry_on (a WAHA pode aprender o mapeamento em minutos).
  def handle_unresolved(session_name, lid, contact_inbox_id)
    return if @waha_skipped || lid.blank?

    record_failure_once(session_name, lid)
    Whatsapp::LidPhoneCache.write_unresolved(session_name, lid)
    Rails.logger.info("[ResolveLidJob] LID #{lid} still unresolved (contact_inbox=#{contact_inbox_id})")
    raise Waha::ApiService::LidNotResolvable, "LID not yet resolvable: #{lid}"
  end

  # Um incremento por CICLO, nao por tentativa: `executions` e 1 na primeira
  # passada e cresce a cada retry_on. Sem isto, as 7 tentativas de um unico ciclo
  # levariam o LID direto ao teto de 7 dias do backoff.
  def record_failure_once(session_name, lid)
    return if lid.blank? || executions.to_i > 1

    count = Whatsapp::LidPhoneCache.record_failure(session_name, lid)
    return if count.zero?

    Rails.logger.info(
      "[ResolveLidJob] LID #{lid} (sessao #{session_name}) falhou #{count}x; " \
      "proxima tentativa so daqui a #{Whatsapp::LidPhoneCache.backoff_for(count)}s"
    )
  end

  # Alimenta o cache com o que acabamos de descobrir e zera a memoria de falha.
  def remember_success(session_name, lid, pn) # rubocop:disable Naming/MethodParameterName
    return if lid.blank?

    Whatsapp::LidPhoneCache.write(session_name, lid, pn)
    Whatsapp::LidPhoneCache.clear_failures(session_name, lid)
  end

  def resolve_lid(waha_service, session_name, lid)
    response = waha_service.get_lid_phone_number(session_name, lid)
    pn = extract_pn(response)
    return pn if pn.present?

    list = waha_service.get_lids_list(session_name, limit: 500, offset: 0)
    return nil unless list.is_a?(Array)

    entry = list.find { |item| (item['lid'] || item[:lid]).to_s == lid.to_s }
    extract_pn(entry || {})
  end

  def extract_pn(hash)
    return nil unless hash.is_a?(Hash)

    hash['pn'].presence || hash[:pn].presence || hash['number'].presence || hash[:number].presence
  end

  def normalize_phone(pn) # rubocop:disable Naming/MethodParameterName
    clean_number = pn.to_s.split('@').first
    return nil if clean_number.blank?

    phone_number = clean_number.start_with?('+') ? clean_number : "+#{clean_number}"
    Contacts::BrazilPhoneNormalizer.normalize(phone_number)
  end

  def merge_or_update(inbox, contact_inbox_by_lid, pn, normalized_phone) # rubocop:disable Naming/MethodParameterName
    contact_inbox_by_pn = inbox.contact_inboxes.find_by(source_id: pn)

    ActiveRecord::Base.transaction do
      if contact_inbox_by_pn.present? && contact_inbox_by_pn.id != contact_inbox_by_lid.id
        # Caso A: ja existe um contact_inbox com source_id == pn (JID do WhatsApp).
        # Mescla o contato @lid no contato dono desse contact_inbox.
        merge_lid_into_pn_contact(inbox, contact_inbox_by_lid, contact_inbox_by_pn, normalized_phone, pn)
      elsif (existing_contact = conflicting_phone_contact(inbox, contact_inbox_by_lid, normalized_phone))
        # Caso B: NAO ha contact_inbox==pn, mas o telefone resolvido ja pertence a
        # OUTRO contato do mesmo account (phone_number e unico por account). Sem este
        # branch, o update! do caminho inline estouraria
        # "ActiveRecord::RecordInvalid: Phone number has already been taken".
        # Mescla o contato @lid no contato real ja existente.
        merge_lid_into_existing_contact(inbox, contact_inbox_by_lid, existing_contact, normalized_phone, pn)
      else
        # Caso C (caminho feliz, sem conflito): normaliza o contact_inbox e o contato.
        update_resolved_contact_inline(contact_inbox_by_lid, pn, normalized_phone)
      end
    end
  rescue ActiveRecord::RecordNotUnique => e
    # Defesa contra corrida: outro worker pode ter resolvido o mesmo LID/telefone em
    # paralelo (ex.: re-sweep + webhook simultaneos). Loga e deixa o retry/re-sweep
    # reconciliar — nao estoura um 500 nem mata o job.
    Rails.logger.warn("[ResolveLidJob] RecordNotUnique ao resolver contact_inbox=#{contact_inbox_by_lid.id}: #{e.message}")
  end

  # Caso A: mantem o contato dono do contact_inbox cujo source_id ja e o pn (JID real).
  def merge_lid_into_pn_contact(inbox, contact_inbox_by_lid, contact_inbox_by_pn, normalized_phone, pn) # rubocop:disable Naming/MethodParameterName
    base_contact = contact_inbox_by_pn.contact
    mergee_contact = contact_inbox_by_lid.contact

    unless base_contact.id == mergee_contact.id
      ContactMergeAction.new(account: inbox.account, base_contact: base_contact, mergee_contact: mergee_contact).perform
    end

    # Ja existe o contact_inbox com o JID; o contact_inbox @lid e redundante.
    contact_inbox_by_lid.reload
    contact_inbox_by_lid.destroy! if contact_inbox_by_lid.persisted?
    clear_residual_lid(base_contact, normalized_phone, pn)

    Rails.logger.info("[ResolveLidJob] Merged LID contact #{mergee_contact.id} into PN contact #{base_contact.id}")
  end

  # Caso B: mescla o contato @lid no contato real que ja possui este telefone.
  def merge_lid_into_existing_contact(inbox, contact_inbox_by_lid, existing_contact, normalized_phone, pn) # rubocop:disable Naming/MethodParameterName
    mergee_contact = contact_inbox_by_lid.contact

    ContactMergeAction.new(account: inbox.account, base_contact: existing_contact, mergee_contact: mergee_contact).perform

    # O ContactMergeAction reatribuiu o contact_inbox @lid ao contato base. Como nao ha
    # contact_inbox==pn neste inbox, normaliza o source_id para o JID (sem colisao).
    contact_inbox_by_lid.reload
    contact_inbox_by_lid.update!(source_id: pn) if contact_inbox_by_lid.persisted? && contact_inbox_by_lid.source_id.to_s.end_with?('@lid')
    clear_residual_lid(existing_contact, normalized_phone, pn)

    Rails.logger.info("[ResolveLidJob] Merged LID contact #{mergee_contact.id} into existing phone contact #{existing_contact.id}")
  end

  # Caminho feliz: sem conflito, atualiza source_id/phone/identifier/name inline.
  def update_resolved_contact_inline(contact_inbox_by_lid, pn, normalized_phone) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
    contact_inbox_by_lid.update!(source_id: pn) if contact_inbox_by_lid.source_id.to_s.end_with?('@lid')
    contact = contact_inbox_by_lid.contact
    contact_updates = {}
    contact_updates[:phone_number] = normalized_phone if normalized_phone.present? && contact.phone_number.blank?
    # Limpa identifier residual com @lid (campo nao deve carregar LID pos-resolucao)
    contact_updates[:identifier] = nil if contact.identifier.to_s.end_with?('@lid')
    # Atualiza nome quando e o proprio LID ou placeholder de widget
    contact_updates[:name] = normalized_phone || pn if contact.name.to_s.end_with?('@lid') || contact.name.to_s.match?(/\A[a-z]+-[a-z]+-\d+\z/)
    contact.update!(contact_updates) if contact_updates.any?

    Rails.logger.info("[ResolveLidJob] Resolved LID (contact_inbox=#{contact_inbox_by_lid.id}) to PN #{pn}")
  end

  # Outro contato do mesmo account que ja possui este telefone (phone_number e unico
  # por account). Detecta o conflito ANTES do update! estourar RecordInvalid.
  def conflicting_phone_contact(inbox, contact_inbox_by_lid, normalized_phone)
    return if normalized_phone.blank?

    inbox.account.contacts
         .where(phone_number: normalized_phone)
         .where.not(id: contact_inbox_by_lid.contact_id)
         .order(last_activity_at: :desc, updated_at: :desc)
         .first
  end

  # Apos um merge, o ContactMergeAction faz deep_merge dos atributos: se o contato base
  # tinha identifier/name vazios, ele HERDA o lixo @lid do mergee. Limpa esse residuo
  # para o contato nao "parecer" um LID nem voltar a ser varrido pelo re-sweep.
  def clear_residual_lid(base_contact, normalized_phone, pn) # rubocop:disable Naming/MethodParameterName
    base_contact.reload
    updates = {}
    updates[:identifier] = nil if base_contact.identifier.to_s.end_with?('@lid')
    updates[:name] = normalized_phone || pn if base_contact.name.to_s.end_with?('@lid')
    base_contact.update!(updates) if updates.any?
  end

  def broadcast_contact_update(contact_inbox, inbox)
    contact = contact_inbox.contact.reload
    account = inbox.account

    Rails.configuration.dispatcher.dispatch(
      'contact.updated',
      Time.zone.now,
      contact: contact,
      account: account
    )
  rescue StandardError => e
    Rails.logger.warn("[ResolveLidJob] Failed to broadcast contact update: #{e.message}")
  end
end
