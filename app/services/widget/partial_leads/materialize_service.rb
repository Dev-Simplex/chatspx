# frozen_string_literal: true

# Bloco 4.18 — o abandono CONFIRMADO vira lead no painel.
#
# O que este servico NAO faz, e e a metade mais importante do aceite: **nao cria
# conversa**. Sem conversa nao ha `conversation_created`, entao o lead incompleto nao
# dispara automacao, nao entra em campanha e nao emite webhook de conversa. Nao e uma
# regra que precisamos escrever — e a consequencia de nao criar a conversa, e o spec
# prova pelos tres lados.
#
# O que ele faz: materializa (ou reencontra) o CONTATO e o marca como incompleto, com a
# ETAPA em que a pessoa parou. Sem canal de contato (e-mail ou WhatsApp) nao materializa
# nada — um cadastro sem forma de responder e lixo no painel do cliente.
class Widget::PartialLeads::MaterializeService
  # Marcadores em `custom_attributes` do contato. Sao os nomes que o painel le para
  # mostrar "lead incompleto" e a etapa; ficam em ingles porque sao CHAVE, nao texto.
  INCOMPLETE_KEY = 'widget_lead_incomplete'
  STEP_KEY = 'widget_lead_step'
  STEP_NAME_KEY = 'widget_lead_step_name'

  def initialize(lead)
    @lead = lead
  end

  # Devolve o Contact materializado, ou nil quando nao havia o que materializar.
  def perform
    return unless sweepable?

    # O abandono e confirmado ANTES da tentativa, e essa ordem e o conserto de um laco
    # infinito. O varredor selecionava so `stale AND contact_id IS NULL` e passa a cada
    # minuto (`config/schedule.yml`); enquanto este servico devolvia nil sem marcar nada —
    # lead sem canal de contato, sem ContactInbox de sessao, ou erro persistente de
    # validacao (um "meu telefone" digitado no campo de telefone reprova em TODA passagem) —
    # a mesma linha voltava aqui ate a retencao vencer: ~43.200 passagens por linha com o
    # cron de 1 minuto e os 30 dias de guarda. Marcada, ela sai do escopo na primeira.
    #
    # O preco: um erro TRANSITORIO tambem carimba, e a linha nao e retentada. E deliberado —
    # perder uma materializacao e menor que remoer a base inteira para sempre, o erro fica
    # no log e a pessoa que volta desfaz a marca.
    confirm_abandonment
    return unless @lead.contactable?

    contact = identify_contact
    return if contact.blank?

    mark_incomplete(contact)
    apply_label(contact)
    @lead.update!(contact: contact)
    contact
  rescue StandardError => e
    Rails.logger.error("Widget::PartialLeads::MaterializeService lead=#{@lead&.id}: #{e.message}")
    nil
  end

  private

  # Quem concluiu nao abandonou, e quem ja tem contato ja foi materializado: nos dois casos
  # o servico nao toca a linha — nem para marcar o abandono.
  def sweepable?
    return false if @lead.blank?

    !@lead.completed? && @lead.contact_id.blank?
  end

  # A marca so pode ser DEFINITIVA enquanto a pessoa nao voltar: `RecordService` limpa
  # `abandoned_at` a cada nova resposta, senao o visitante que retorna e finalmente da o
  # e-mail ficaria fora do varredor para sempre — o conserto do laco viraria lead perdido.
  def confirm_abandonment
    @lead.update!(abandoned_at: Time.current) if @lead.abandoned_at.blank?
  end

  # Reusa o ContactInbox da propria sessao quando ele existe (o widget cria um no boot),
  # em vez de inventar um contato solto: assim o lead incompleto e o MESMO cadastro que a
  # pessoa usaria se voltasse e concluisse — que e o que impede o painel de ter duas
  # fichas da mesma pessoa.
  def identify_contact
    contact = session_contact
    return if contact.blank?

    ContactIdentifyAction.new(
      contact: contact,
      params: { email: @lead.email, phone_number: @lead.phone_number, name: @lead.name }.compact_blank,
      retain_original_contact_name: true
    ).perform
  end

  def session_contact
    ContactInbox.find_by(inbox_id: @lead.inbox_id, source_id: @lead.session_id)&.contact
  end

  def mark_incomplete(contact)
    attributes = contact.custom_attributes.to_h.merge(
      INCOMPLETE_KEY => true,
      STEP_KEY => @lead.step_reached,
      STEP_NAME_KEY => @lead.step_key
    ).compact
    contact.update!(custom_attributes: attributes)
  end

  # Etiqueta configuravel (mockup 22 §3: "Etiquetar como `lead-incompleto`"). Vazio
  # desliga a etiqueta sem desligar a captura. `add_labels` e aditivo — nao apaga as
  # etiquetas que o agente ja tenha posto.
  def apply_label(contact)
    label = Widget::PartialLeads::Settings.new(contact.account).label
    return if label.blank?

    contact.add_labels([label])
  end
end
