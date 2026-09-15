require 'rails_helper'

# Medido na Catatau (conta 1, caixa 7) em 15/09: as 45 conversas vindas de anúncio caíram em 5
# times diferentes, porque quem escolhia o time era o menu — ou seja, o lead. Quem paga o
# anúncio quer o contrário.
RSpec.describe Whatsapp::ReferralTeamRoutingService do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:inbox) do
    create(:inbox, account: account,
                   additional_attributes: { 'ad_referral_routing_enabled' => true, 'ad_referral_team_id' => team.id })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Payload real de um anúncio da Catatau (15/09), encurtado.
  let(:referral) do
    {
      'source_url' => 'https://www.instagram.com/p/DdB5PqMMPh7/',
      'source_id' => '120251471800180551',
      'source_type' => 'ad',
      'headline' => 'Simule agora',
      'body' => '🚘 Hyundai HB20S 1.0 Turbo Flex Automático 2025'
    }
  end

  def mensagem(attrs)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: 'Oi', content_attributes: attrs)
  end

  def rotear(msg)
    described_class.new(message: msg).perform
    conversation.reload
  end

  it 'sends the ad lead straight to the team chosen in the inbox' do
    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to eq(team.id)
  end

  it 'does nothing when the inbox has the routing turned off' do
    inbox.update!(additional_attributes: inbox.additional_attributes.merge('ad_referral_routing_enabled' => false))

    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to be_nil
  end

  it 'does nothing when no team was chosen' do
    inbox.update!(additional_attributes: { 'ad_referral_routing_enabled' => true })

    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to be_nil
  end

  # Todo o resto do inbound (orgânico, resposta de template, story reply) passa por aqui.
  it 'does nothing for a message without referral' do
    rotear(mensagem({}))

    expect(conversation.team_id).to be_nil
  end

  # O flow de triagem carimba o time no conversation.created, despachado ANTES do message.created:
  # esperar "conversa sem time" faria o roteamento do anúncio nunca acontecer.
  it 'wins over the automatic triage that already set a team on the brand new conversation' do
    triagem = create(:team, account: account)
    conversation.update!(team_id: triagem.id)

    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to eq(team.id)
  end

  # Trocar o time no meio do atendimento tira a conversa de quem já estava nela e, em caixa com
  # isolamento de time, esconde as mensagens anteriores de quem recebeu.
  it 'keeps the current team when the ad message lands on a conversation already in progress' do
    outro_time = create(:team, account: account)
    mensagem({})
    conversation.update!(team_id: outro_time.id)

    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to eq(outro_time.id)
  end

  # Time apagado (ou de outra conta) não pode virar um update com id inválido.
  it 'ignores a team that does not belong to the account' do
    inbox.update!(additional_attributes: inbox.additional_attributes.merge('ad_referral_team_id' => create(:team).id))

    rotear(mensagem({ 'referral' => referral }))

    expect(conversation.team_id).to be_nil
  end

  # Sem rastro, o time lê a atividade anterior ("Atribuído a triagem") como se fosse a verdade.
  it 'leaves the reason on the conversation timeline' do
    expect { rotear(mensagem({ 'referral' => referral })) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation.id, hash_including(message_type: :activity))
  end

  it 'never breaks message delivery when the routing fails' do
    msg = mensagem({ 'referral' => referral })
    allow(conversation).to receive(:update!).and_raise(StandardError, 'boom')
    allow(msg).to receive(:conversation).and_return(conversation)

    expect { described_class.new(message: msg).perform }.not_to raise_error
  end
end
