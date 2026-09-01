require 'rails_helper'

# O lead de FORMULÁRIO já era carimbado; o CTWA entra por outra porta (a pessoa escreve primeiro)
# e ficava invisível. Medido na Tozi, 45 dias: 167 conversas vindas de anúncio, 155 sem nenhum
# atributo de campanha.
RSpec.describe Whatsapp::ReferralVisibilityService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Payload real de um anúncio da conta 6 (16/08), encurtado.
  let(:referral) do
    {
      'source_url' => 'https://www.instagram.com/p/Db9A_T3sTj_/',
      'source_id' => '120250773909710544',
      'source_type' => 'ad',
      'headline' => 'Casa nova por muito menos',
      'body' => 'Essa casa vale R$ 235 mil na tabela… mas você não paga isso.',
      'ctwa_clid' => 'AfjeYapiJOD'
    }
  end

  def mensagem(attrs)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: 'Oi', content_attributes: attrs)
  end

  def carimbar(msg)
    described_class.new(message: msg).perform
    conversation.reload
  end

  it 'stamps where the conversation came from, using the headline the team recognises' do
    carimbar(mensagem({ 'referral' => referral }))

    expect(conversation.custom_attributes['meta_anuncio']).to eq('Casa nova por muito menos')
    expect(conversation.custom_attributes['meta_anuncio_id']).to eq('120250773909710544')
    expect(conversation.custom_attributes['meta_origem']).to eq('Instagram')
    expect(conversation.custom_attributes['meta_tipo']).to eq('Clique no anúncio')
  end

  it 'labels the conversation so the team can filter what came from ads' do
    carimbar(mensagem({ 'referral' => referral }))

    expect(conversation.label_list).to include('anuncio')
  end

  it 'reads the origin from the source url' do
    carimbar(mensagem({ 'referral' => referral.merge('source_url' => 'https://fb.me/4QypGbDUW') }))

    expect(conversation.custom_attributes['meta_origem']).to eq('Facebook')
  end

  # Sem headline o id cru não diz nada a quem trabalha com a peça; o começo do corpo diz.
  it 'falls back to the ad copy when there is no headline' do
    carimbar(mensagem({ 'referral' => referral.except('headline') }))

    expect(conversation.custom_attributes['meta_anuncio']).to start_with('Essa casa vale')
  end

  # A conversa é única por contato: o que se quer saber é por onde ela COMEÇOU.
  it 'keeps the first ad when the person clicks another one later' do
    carimbar(mensagem({ 'referral' => referral }))
    carimbar(mensagem({ 'referral' => referral.merge('headline' => 'Saia do aluguel', 'source_id' => '999') }))

    expect(conversation.custom_attributes['meta_anuncio']).to eq('Casa nova por muito menos')
    expect(conversation.custom_attributes['meta_anuncio_id']).to eq('120250773909710544')
  end

  # Todo o resto do inbound (orgânico, story reply, resposta de template) passa por aqui.
  it 'does nothing for a message without referral' do
    carimbar(mensagem({ 'in_reply_to_external_id' => nil }))

    expect(conversation.custom_attributes).to be_blank
    expect(conversation.label_list).to be_empty
  end

  it 'never breaks message delivery when the stamp fails' do
    msg = mensagem({ 'referral' => referral })
    allow(conversation).to receive(:update!).and_raise(StandardError, 'boom')
    allow(msg).to receive(:conversation).and_return(conversation)

    expect { described_class.new(message: msg).perform }.not_to raise_error
  end
end
