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
# So age na PRIMEIRA mensagem recebida da conversa, e nao "so quando a conversa esta sem time":
# medido na Catatau em 15/09, o flow de triagem carimba o time no `conversation.created`, que e
# despachado antes do `message.created` — a conversa ja nasce com time e o roteamento do anuncio
# nunca aconteceria. Quem paga o anuncio escolheu o destino, entao aqui ele ganha da triagem
# automatica. Ja mensagem de anuncio que cai numa conversa em andamento (contato que voltou,
# conversa reaberta) nao muda o dono: trocar o time no meio do atendimento tira a conversa de
# quem estava nela e, em caixa com isolamento de time, esconde as mensagens anteriores de quem
# recebeu.
class Whatsapp::ReferralTeamRoutingService
  pattr_initialize [:message!]

  def perform
    return unless roteavel?

    conversation.update!(team_id: team.id)
    registrar_atividade
    distribuir
    Rails.logger.info("[ReferralTeamRouting] conv=#{conversation.id} team=#{team.id}")
  rescue StandardError => e
    # Roteamento nunca pode derrubar o recebimento de mensagem.
    Rails.logger.warn("[ReferralTeamRouting] conv=#{conversation&.id}: #{e.class}: #{e.message}")
  end

  private

  # Definir o time nao da dono ao lead, e sem dono ele aparece para o time inteiro: na Catatau
  # isso pos dois vendedores na mesma conversa (conv 196, 15/09, Rodrigo e Adrian falando com a
  # mesma cliente). O Motor de Distribuicao so era acionado pelo no `distribuir` do flow, ou
  # seja, DEPOIS que o cliente responde o menu — e o lead de anuncio nao passa por menu nenhum.
  # Chamar aqui e o que fecha o caminho: quem escolheu o destino tambem decide o dono.
  #
  # Best-effort: o proprio Motor tem rescue e devolve no-op quando nao ha politica, pool ou
  # quando o lead ja tem dono. Falhar aqui nao pode desfazer o direcionamento de time.
  def distribuir
    Spx::Distribuicao::DistribuirService.new(conversation).call
  rescue StandardError => e
    Rails.logger.warn("[ReferralTeamRouting] distribuicao conv=#{conversation.id}: #{e.class}: #{e.message}")
  end

  # A atividade nativa de troca de time so nasce quando ha autor no `Current` (ver
  # AssigneeActivityMessageHandler#activity_message_owner), e aqui nao ha: a conversa mudaria de
  # dono sem rastro nenhum e o time leria a atividade anterior ("Atribuido a triagem") como se
  # fosse a verdade. O texto proprio diz o motivo, que "por Sistema de Automacao" nao diria.
  def registrar_atividade
    Conversations::ActivityMessageJob.perform_later(
      conversation.id,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
        content: I18n.t('conversations.activity.team.assigned_from_ad', team_name: team.name) }
    )
  end

  def roteavel?
    referral.present? && conversation.present? && primeira_mensagem? && routing_enabled? &&
      team.present? && conversation.team_id != team.id
  end

  # Primeira mensagem DO CLIENTE: o flow ja respondeu antes daqui (saudacao, menu), entao contar
  # mensagem de qualquer direcao diria que a conversa tem historico quando ela acabou de nascer.
  def primeira_mensagem?
    conversation.messages.incoming.where(messages: { id: ...message.id }).none?
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
