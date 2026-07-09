# frozen_string_literal: true

# Guardas de compliance do motor Flow (gap-BR WhatsApp marketing), misturadas no
# Flows::ActionService e aplicadas IMEDIATAMENTE antes de send_message/send_template enviarem.
# Cada bloqueio levanta um Flows::StepSkip tipado — o #execute o captura como `skipped` (sem
# Sentry) e o Runner o registra num FlowStepLog triável (error_code = o código do skip).
# Depende do host (ActionService): @conversation, @account e o helper template_matches?.
module Flows::Compliance
  # Teto de mensagens de MARKETING por contato na janela abaixo antes de barrar novos envios de
  # marketing. SÓ marketing conta (utility/authentication/service não — risco R-6). Default
  # conservador (1/dia); sobrescrevível por conta via internal_attributes['flows_marketing_daily_cap'].
  MARKETING_DAILY_CAP = 1
  # Janela móvel do cap de marketing (também é a janela de sessão de 24h do WhatsApp).
  MARKETING_WINDOW = 24.hours

  private

  # Ordem: opt-out (contato pediu pra parar) → cap de marketing (limite diário) → janela 24h (só
  # mensagem livre). `category` é o balde do envio ('marketing'|'utility'); `free_form` marca
  # texto livre (send_message), o único que exige a janela — templates saem fora dela.
  #   suppressed_opt_out → há suppression ATIVA pro balde (ou `all`)
  #   marketing_cap      → já atingiu o cap de marketing/contato na janela
  #   outside_window     → texto livre fora da janela de 24h (conversation.can_reply? == false)
  def enforce_compliance!(category:, free_form:)
    contact = @conversation.contact

    if ContactFlowSuppression.suppressed?(contact, category)
      raise Flows::StepSkip.new('suppressed_opt_out', "contact is suppressed for #{category} messages")
    end

    if category == 'marketing' && marketing_cap_reached?(contact)
      raise Flows::StepSkip.new('marketing_cap', "marketing daily cap (#{marketing_daily_cap}) reached for the contact")
    end

    return unless free_form && !@conversation.can_reply?

    raise Flows::StepSkip.new('outside_window', 'outside the 24h messaging window (free-form only)')
  end

  # Traduz a categoria WhatsApp do template (MARKETING/UTILITY/AUTHENTICATION/…) no balde de
  # compliance. SÓ MARKETING é 'marketing'; todo o resto é 'utility' (não-marketing) — assim
  # opt-out (PARAR) e o cap NUNCA tocam utility/service (risco R-6). Categoria vem do metadata
  # REAL do template na inbox (mesmo casamento nome+idioma+aprovado do approved_template?).
  def compliance_category(template)
    whatsapp_category(template).to_s.upcase == 'MARKETING' ? 'marketing' : 'utility'
  end

  def whatsapp_category(template)
    templates = @conversation.inbox.channel.message_templates
    return if templates.blank?

    match = templates.find { |candidate| template_matches?(candidate, template) }
    match && match['category']
  end

  # Cap atingido? Conta as mensagens de MARKETING já entregues AO contato (via suas conversas na
  # conta) na janela móvel. Uma mensagem é "de marketing" quando seu template_params.name está
  # entre os templates MARKETING da inbox atual. A mensagem deste envio ainda NÃO existe (a
  # guarda roda antes de montar), então o 1º marketing passa (count 0) e o (cap+1)-ésimo é
  # barrado. Limitação documentada: nomes de marketing vêm da inbox ATUAL (multi-inbox raro).
  def marketing_cap_reached?(contact)
    return false if contact.blank?

    names = marketing_template_names
    return false if names.blank?

    conversation_ids = contact.conversations.where(account_id: @account.id).select(:id)
    sent = Message.where(conversation_id: conversation_ids, message_type: %i[outgoing template])
                  .where('messages.created_at >= ?', MARKETING_WINDOW.ago)
                  .where("messages.additional_attributes -> 'template_params' ->> 'name' IN (?)", names)
                  .count
    sent >= marketing_daily_cap
  end

  # Nomes dos templates MARKETING aprovados na inbox atual — o conjunto contra o qual as
  # mensagens passadas são contadas no cap. Vazio quando a inbox não tem templates de marketing.
  def marketing_template_names
    templates = @conversation.inbox.channel.message_templates
    return [] if templates.blank?

    templates.select { |t| t['category'].to_s.upcase == 'MARKETING' }.filter_map { |t| t['name'] }.uniq
  end

  # Teto efetivo: override por conta (internal_attributes) quando presente, senão a constante.
  # Torna o cap "configurável" sem migração — a fatia de admin pode gravar a chave por conta.
  def marketing_daily_cap
    configured = (@account.internal_attributes || {})['flows_marketing_daily_cap']
    configured.present? ? configured.to_i : MARKETING_DAILY_CAP
  end
end
