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

  # O canal é materializado ANTES de qualquer re-stub: `create` dispara `after_create_commit
  # :subscribe`, e o factory registra o stub daquela chamada. Configurar ou re-stubar antes disso
  # faria o próprio `create` bater num stub que não existe.
  describe '#subscribed_fields' do
    before { channel }

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
    # Regex, e não URL literal: o stub precisa casar independentemente da query, que é justamente
    # o que varia entre a tentativa com os campos extras e o recuo para o núcleo.
    let(:url) { %r{https://graph\.instagram\.com/v22\.0/#{channel.instagram_id}/subscribed_apps} }

    before do
      # Criar o canal JÁ dispara um `subscribe` (`after_create_commit`). Sem zerar o registro, a
      # contagem de requisições de cada exemplo começaria em 1. Isto limpa o que foi requisitado,
      # não os stubs.
      channel
      WebMock::RequestRegistry.instance.reset!
    end

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
      stub_request(:post, url).to_return do |request|
        if request.uri.query.to_s.include?('comments')
          { status: 400, body: { error: { message: 'Invalid parameter' } }.to_json }
        else
          { status: 200, body: '' }
        end
      end

      # São DUAS linhas de log, e as duas importam: a recusa (com o corpo da resposta da Meta) e
      # o recuo (dizendo que os campos extras ficaram de fora).
      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(/falha ao assinar .*comments/).and_call_original
      expect(Rails.logger).to receive(:error).with(/recuando para/).and_call_original

      expect(channel.subscribe).to be true
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it 'não tenta o núcleo duas vezes quando não há campo extra configurado' do
      stub_request(:post, url).to_return(status: 400, body: '')

      expect(channel.subscribe).to be false
      expect(a_request(:post, url)).to have_been_made.once
    end
  end

  def configurar(valor)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_SUBSCRIBED_FIELDS', '').and_return(valor)
  end
end
