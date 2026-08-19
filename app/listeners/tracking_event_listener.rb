class TrackingEventListener < BaseListener
  # Bloco 5.03 — os fatos que SO o servidor conhece viram evento de tracking aqui.
  #
  # Sao dois:
  #  · `chatspx_conversation_resolved` (evento #10 do contrato), aceite do bloco 5.03;
  #  · `chatspx_lead` (evento #5), acrescentado pelo bloco 5.04 (T-C3.7).
  #
  # A regra RG4 do plano 25 continua valendo — "uma emissao por fato" — e o `chatspx_lead` NAO a
  # viola: o widget emite o evento de `window` `chatwoot:lead-identified`, que e o outro
  # VOCABULARIO do mesmo fato (arbitragem A9), e nao um segundo evento de tracking. O evento de
  # tracking, o que vai a Meta e ao GA4, nasce so aqui.
  #
  # Os demais eventos do widget (#1 a #4, #6 a #9) continuam nascendo no store — bloco 5.04 — e nao
  # devem ser emitidos daqui tambem.
  #
  # Acrescentar um fato server-side custa um metodo com o mesmo formato — a infraestrutura aceita
  # qualquer nome que obedeca ao contrato.
  #
  # Este listener vive no AsyncDispatcher (roda UMA vez por fato, via EventDispatcherJob) e nunca no
  # SyncDispatcher, que dispararia o mesmo fato duas vezes.

  # Os dois identificadores que o contrato chama de lead (§A.6 evento #5).
  LEAD_IDENTIFIER_COLUMNS = %w[email phone_number].freeze
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]

    record_conversation_resolved(conversation, event.timestamp)
  rescue StandardError => e
    # Observabilidade nunca quebra o produto: se o registro falhar, a conversa continua resolvida.
    # E a mesma regra do FlowStepLog desta base — o log e best-effort, o fluxo nao.
    ChatwootExceptionTracker.new(e, account: conversation_account(event)).capture_exception
  end

  # T-C3.7 / bloco 5.04 — `chatspx_lead` (evento #5 do contrato).
  #
  # "O contato passou a ter e-mail OU telefone" e um fato que SO o servidor conhece com certeza,
  # e a razao esta na palavra PASSOU: e uma transicao, nao um estado. O widget ve o estado
  # ("este contato tem e-mail") e nao consegue distinguir o visitante que acabou de digitar do
  # visitante que ja era identificado e recarregou a pagina. Emitir do cliente contaria um Lead
  # por carregamento — conversao inflada, decisao de midia sobre numero mentiroso.
  #
  # Aqui a transicao e verificavel: `previous_changes` diz de onde para onde o campo foi.
  def contact_created(event)
    contact = extract_contact_and_account(event)[0]
    return if lead_identifiers_of(contact).empty?

    record_lead(contact, event.timestamp)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: contact_account(event)).capture_exception
  end

  def contact_updated(event)
    contact = extract_contact_and_account(event)[0]
    return unless became_lead?(event.data[:changed_attributes])

    record_lead(contact, event.timestamp)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: contact_account(event)).capture_exception
  end

  private

  # Nomes, nunca valores: o que sai daqui alimenta `properties`, e `TrackingEvent` RECUSA chave de
  # PII crua — a PII do lead sai hasheada pelo servidor em 5.11, de outro lugar.
  def lead_identifiers_of(contact)
    LEAD_IDENTIFIER_COLUMNS.select { |coluna| contact.public_send(coluna).present? }
  end

  # Transicao de verdade: o campo estava vazio e passou a ter valor. Um contato que TROCA de
  # e-mail nao vira lead de novo — ele ja era.
  def became_lead?(changed_attributes)
    return false if changed_attributes.blank?

    LEAD_IDENTIFIER_COLUMNS.any? do |coluna|
      antes, depois = Array(changed_attributes[coluna] || changed_attributes[coluna.to_sym])
      antes.blank? && depois.present?
    end
  end

  def record_lead(contact, occurred_at)
    conversation = contact.conversations.order(created_at: :desc).first

    Tracking::EventRecorder.record!(
      name: 'chatspx_lead',
      account: contact.account,
      inbox: conversation&.inbox,
      conversation: conversation,
      contact: contact,
      occurred_at: occurred_at,
      properties: { 'lead_source' => lead_source_of(conversation) },
      # CHAVE NATURAL DO FATO, e ela e o que impede o evento de nascer duas vezes.
      #
      # Sem ela a derivacao usa `occurred_at.to_i`: um contato que ganha e-mail as 10h00m01s e
      # telefone as 10h00m09s produziria DOIS `chatspx_lead` — dois `event_id`, duas conversoes
      # na Meta, e o indice de (evento, destino) nao tocaria em nenhuma, porque para o banco sao
      # eventos diferentes. Com a chave presa ao contato, a segunda transicao devolve o MESMO
      # registro (contrato §4.2).
      dedup_key: "chatspx_lead:contact:#{contact.id}"
    )
  end

  # `value` e `currency` do evento #5 NAO saem daqui de proposito: eles vem da configuracao de
  # tracking da conta (bloco 5.01), que ainda nao existe. Inventar um valor seria pior que a
  # ausencia — o destino contaria receita que ninguem configurou. Na ausencia, a Meta e o GA4
  # recebem a conversao sem valor monetario, que e o comportamento correto ate 5.01 entregar.
  def lead_source_of(conversation)
    conversation&.inbox&.channel_type.presence || 'contact'
  end

  def contact_account(event)
    event.data[:contact]&.account
  rescue StandardError
    nil
  end

  def record_conversation_resolved(conversation, resolved_at)
    Tracking::EventRecorder.record!(
      name: 'chatspx_conversation_resolved',
      account: conversation.account,
      inbox: conversation.inbox,
      conversation: conversation,
      contact: conversation.contact,
      occurred_at: resolved_at,
      properties: {
        'resolution' => resolution_of(conversation),
        'duration_s' => resolved_at.to_i - conversation.created_at.to_i
      }
    )
  end

  # Os dois parametros que o contrato declara para o evento #10. `resolution` responde "quem
  # resolveu" com o unico dado que o servidor tem sem inventar: conversa sem responsavel foi
  # resolvida sem humano.
  def resolution_of(conversation)
    conversation.assignee_id.present? ? 'agent' : 'bot'
  end

  def conversation_account(event)
    event.data[:conversation]&.account
  rescue StandardError
    nil
  end
end
