# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Instagram do
  let(:channel) { create(:channel_instagram) }

  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:instagram_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  it 'has a valid name' do
    expect(channel.name).to eq('Instagram')
  end

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for instagram' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:instagram_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end

  describe '#subscribed_fields' do
    it 'devolve só o núcleo quando não há configuração' do
      expect(channel.subscribed_fields).to eq(%w[messages message_reactions messaging_seen])
    end

    it 'acrescenta os campos configurados na instalação' do
      configurar('comments')

      expect(channel.subscribed_fields).to eq(%w[messages message_reactions messaging_seen comments])
    end

    # A configuração ACRESCENTA. Quem escrever só `comments` não fica sem DM.
    it 'não deixa a configuração remover o núcleo' do
      configurar('comments, messages')

      expect(channel.subscribed_fields).to eq(%w[messages message_reactions messaging_seen comments])
    end
  end

  describe '#subscribe' do
    let(:url) { "https://graph.instagram.com/v22.0/#{channel.instagram_id}/subscribed_apps" }

    # O defeito de fundo: `HTTParty.post` NÃO levanta exceção em HTTP 400, então o
    # `rescue StandardError` de antes só pegava falha de rede. Recusa da Meta passava por sucesso
    # e o canal ficava sem assinatura, sem nada em lugar nenhum dizendo isso.
    it 'não trata recusa da Meta como sucesso' do
      stub_request(:post, url).to_return(
        status: 400,
        body: { error: { message: 'Invalid parameter', code: 100 } }.to_json
      )

      expect(channel.subscribe).to be false
    end

    it 'trata erro no corpo de uma resposta 200 como falha' do
      stub_request(:post, url).to_return(
        status: 200,
        body: { error: { message: 'Permissions error' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect(channel.subscribe).to be false
    end

    # A armadilha que isto fecha: a lista vai INTEIRA numa chamada só. Um campo que o app da box
    # não tem derrubava o lote e o canal ficava sem assinatura NENHUMA — DM morta em silêncio.
    it 'recua para o núcleo quando o lote completo é recusado, e diz o que perdeu' do
      configurar('comments')
      stub_request(:post, url)
        .with(query: hash_including({ 'subscribed_fields' => %w[messages message_reactions messaging_seen comments] }))
        .to_return(status: 400, body: { error: { message: 'Invalid parameter' } }.to_json)
      nucleo = stub_request(:post, url)
               .with(query: hash_including({ 'subscribed_fields' => %w[messages message_reactions messaging_seen] }))
               .to_return(status: 200, body: '')

      expect(Rails.logger).to receive(:error).with(/recuando para/).and_call_original
      expect(channel.subscribe).to be true
      expect(nucleo).to have_been_requested
    end

    it 'não tenta o núcleo duas vezes quando não há campo extra configurado' do
      pedido = stub_request(:post, url).to_return(status: 400, body: '')

      expect(channel.subscribe).to be false
      expect(pedido).to have_been_requested.once
    end
  end

  def configurar(valor)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_SUBSCRIBED_FIELDS', '').and_return(valor)
  end
end
