# frozen_string_literal: true

# Bloco 4.18 — grava a resposta PARCIAL do pre-chat. Chamado a cada campo respondido,
# ANTES de existir conversa.
#
# IDEMPOTENTE POR SESSAO: a chave e (inbox_id, session_id), com indice UNICO no banco.
# "Retomar na mesma sessao nao duplica o registro" e garantia do banco, nao do servico —
# duas requisicoes simultaneas do mesmo visitante nao criam duas linhas: a segunda colide
# no indice e cai no caminho de atualizacao.
#
# As respostas sao MESCLADAS: o visitante que volta e corrige o e-mail sobrescreve o
# campo, sem apagar os outros. Campo enviado vazio APAGA a resposta anterior — voltar e
# limpar um campo e uma acao deliberada da pessoa, e o registro precisa refleti-la (LGPD:
# nao guardamos o que ela retirou).
class Widget::PartialLeads::RecordService
  # Teto de campos gravados, espelhando o teto de 8 do fluxo de captura
  # (Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS). Um cliente do endpoint nao decide
  # quanto dado pessoal cabe numa linha nossa.
  MAX_ANSWERS = Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS
  MAX_KEY_LENGTH = 100
  MAX_VALUE_LENGTH = 500

  def initialize(inbox:, session_id:, answers:, step: nil, step_key: nil)
    @inbox = inbox
    @session_id = session_id.to_s
    @answers = answers
    @step = step
    @step_key = step_key
  end

  # Devolve o WidgetPartialLead gravado, ou nil quando a captura esta desligada / falta
  # material. NUNCA levanta: uma falha aqui nao pode impedir o visitante de conversar.
  def perform
    return unless eligible?

    lead = WidgetPartialLead.find_or_initialize_by(inbox_id: @inbox.id, session_id: @session_id)
    lead.account_id = @inbox.account_id
    apply_answer(lead)
    lead.save!
    lead
  rescue ActiveRecord::RecordNotUnique
    # Corrida entre duas respostas quase simultaneas da MESMA sessao: o indice unico
    # ganhou, e a linha ja existe. Tentar de novo agora encontra e atualiza.
    retry_once
  rescue StandardError => e
    Rails.logger.error("Widget::PartialLeads::RecordService inbox=#{@inbox&.id}: #{e.message}")
    nil
  end

  private

  def eligible?
    return false if @inbox.blank? || @session_id.blank?
    return false unless @inbox.web_widget?
    return false unless Widget::PartialLeads::Settings.new(@inbox.account).enabled?

    sanitized_answers.present?
  end

  # O que uma nova resposta faz com a linha. Mora num metodo so porque os DOIS caminhos de
  # gravacao (o normal e o `retry_once` da corrida) precisam aplicar exatamente as mesmas
  # regras — inclusive a ultima, que e a menos obvia.
  #
  # `abandoned_at = nil`: respondeu de novo, entao NAO esta mais abandonado. A marca e o que
  # tira a linha do laco do varredor (`SweepJob#materialize_abandoned`); mante-la aqui
  # deixaria fora do varredor para sempre exatamente quem voltou e finalmente deu o e-mail.
  def apply_answer(lead)
    lead.answers = merged_answers(lead)
    lead.step_reached = [@step.to_i, lead.step_reached.to_i].max
    lead.step_key = @step_key.to_s.presence || lead.step_key
    lead.last_answered_at = Time.current
    lead.abandoned_at = nil
  end

  def retry_once
    lead = WidgetPartialLead.find_by(inbox_id: @inbox.id, session_id: @session_id)
    return nil if lead.blank?

    apply_answer(lead)
    lead.save!
    lead
  rescue StandardError
    nil
  end

  def merged_answers(lead)
    lead.answers.to_h.merge(sanitized_answers).reject { |_key, value| value.to_s.strip.blank? }.first(MAX_ANSWERS).to_h
  end

  # O corpo vem do NAVEGADOR do visitante: chave e valor sao truncados e o numero de
  # campos e limitado antes de tocar o banco. Sem isto, um cliente adulterado escreveria
  # um jsonb arbitrario na base do cliente.
  def sanitized_answers
    @sanitized_answers ||= @answers.to_h.filter_map do |key, value|
      name = key.to_s.strip.slice(0, MAX_KEY_LENGTH)
      next if name.blank?

      [name, value.to_s.strip.slice(0, MAX_VALUE_LENGTH)]
    end.first(MAX_ANSWERS).to_h
  end
end
