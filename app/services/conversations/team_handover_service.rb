# Quem puxa para si uma conversa de outro time leva a conversa junto.
#
# Sem isto a tela se contradiz: em caixa com isolamento por time, o agente assumiria uma conversa
# que, um segundo depois, ele não consegue abrir — e ela sumiria da lista dele.
class Conversations::TeamHandoverService
  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
  end

  def perform
    return unless @user.is_a?(User)
    return if ja_e_do_meu_time?

    # Com mais de um time vale o primeiro por nome: previsível, e sem perguntar nada na hora do
    # clique. Sem time nenhum a conversa fica SEM time — é o que a mantém visível para quem
    # acabou de assumir, em vez de presa no time de onde ela veio.
    @conversation.update!(team_id: meu_primeiro_time&.id)
  end

  private

  def ja_e_do_meu_time?
    @conversation.team_id.present? && meus_times.exists?(id: @conversation.team_id)
  end

  def meu_primeiro_time
    meus_times.order(:name).first
  end

  def meus_times
    @meus_times ||= @user.teams.where(account_id: @conversation.account_id)
  end
end
