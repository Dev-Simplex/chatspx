# Manda o lead que chegou por anuncio de clique-para-WhatsApp (CTWA) direto para um time,
# escolhido na configuracao da propria caixa de entrada.
#
# O carimbo de origem ja existia (Whatsapp::ReferralVisibilityService): a conversa recebia
# `meta_anuncio` e a label `anuncio`, mas continuava sem dono. Medido na Catatau (conta 1,
# caixa 7) em 15/09: as 45 conversas vindas de anuncio caem em 5 times diferentes porque quem
# decide o time e o menu do flow, ou seja, o lead. Quem paga o anuncio quer o contrario: o
# lead cai no time da campanha sem passar por menu.
#
# Config na caixa (`inbox.additional_attributes`, sem migration):
#   ad_referral_routing_enabled => liga/desliga
#   ad_referral_team_id         => time de destino
#
# So age em conversa SEM time. Mensagem de anuncio que cai numa conversa ja em atendimento
# (contato que voltou, conversa reaberta) nao muda o dono: trocar o time no meio do
# atendimento tira a conversa de quem ja estava nela e, em caixa com isolamento de time,
# esconde as mensagens anteriores de quem recebeu.
class Whatsapp::ReferralTeamRoutingService
  pattr_initialize [:message!]

  def perform
    return unless roteavel?

    conversation.update!(team_id: team.id)
    Rails.logger.info("[ReferralTeamRouting] conv=#{conversation.id} team=#{team.id}")
  rescue StandardError => e
    # Roteamento nunca pode derrubar o recebimento de mensagem.
    Rails.logger.warn("[ReferralTeamRouting] conv=#{conversation&.id}: #{e.class}: #{e.message}")
  end

  private

  def roteavel?
    referral.present? && conversation.present? && conversation.team_id.blank? && routing_enabled? && team.present?
  end

  def conversation
    @conversation ||= message.conversation
  end

  def inbox
    @inbox ||= message.inbox
  end

  def referral
    @referral ||= (message.content_attributes || {})['referral'].presence
  end

  def routing_enabled?
    ActiveModel::Type::Boolean.new.cast(inbox.additional_attributes.to_h['ad_referral_routing_enabled'])
  end

  # Le o time pela conta, e nao por id solto: caixa configurada com um time que foi apagado
  # (ou de outra conta) nao pode virar um update com id invalido.
  def team
    return @team if defined?(@team)

    team_id = inbox.additional_attributes.to_h['ad_referral_team_id'].presence
    @team = team_id.blank? ? nil : inbox.account.teams.find_by(id: team_id)
  end
end
