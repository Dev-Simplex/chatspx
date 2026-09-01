require 'rails_helper'

RSpec.describe Spx::Social::LerMidiaDaPublicacao do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_instagram, account: account, instagram_id: '17841468839878751') }
  let(:inbox) { channel.inbox }
  let(:publicacao) do
    create(:social_publicacao, account: account, inbox: inbox, external_id: 'pub-1')
  end

  def ligar(valor: true)
    account.update!(settings: (account.settings || {}).merge('social_reply' => { 'ler_midia' => valor }))
    account.reload
  end

  def stub_media(media_type:, filhos: nil)
    stub_request(:get, %r{graph\.instagram\.com/v22\.0/pub-1\?})
      .to_return(status: 200, body: { media_type: media_type, media_url: 'https://cdn/x.jpg' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    return if filhos.nil?

    stub_request(:get, %r{graph\.instagram\.com/v22\.0/pub-1/children})
      .to_return(status: 200, body: { data: filhos }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def leitor_devolve(*textos)
    leitores = textos.map { |t| instance_double(Spx::Social::LeitorDeMidia, perform: t) }
    allow(Spx::Social::LeitorDeMidia).to receive(:new).and_return(*leitores)
  end

  # Opt-in por conta: quem não ligar não paga visão nenhuma.
  it 'não faz nada sem a chave ligada' do
    expect(described_class.new(publicacao: publicacao).perform).to eq(:desligada)
    expect(publicacao.reload.lida_em).to be_nil
  end

  context 'when it is on' do
    before { ligar }

    it 'lê cada item do carrossel e guarda numerado' do
      stub_media(media_type: 'CAROUSEL_ALBUM', filhos: [
                   { id: '1', media_type: 'IMAGE', media_url: 'https://cdn/1.jpg' },
                   { id: '2', media_type: 'IMAGE', media_url: 'https://cdn/2.jpg' }
                 ])
      leitor_devolve('Coca Cola 2L por R$ 7,99', 'Arroz 5kg por R$ 24,90')

      expect(described_class.new(publicacao: publicacao).perform).to eq(:lida)
      leitura = publicacao.reload.leitura_midia
      expect(leitura).to include('[imagem 1] Coca Cola 2L por R$ 7,99')
      expect(leitura).to include('[imagem 2] Arroz 5kg por R$ 24,90')
      expect(publicacao.lida_em).to be_present
    end

    it 'lê a própria mídia quando a publicação não é carrossel' do
      stub_media(media_type: 'IMAGE')
      leitor_devolve('Promoção de agosto')

      expect(described_class.new(publicacao: publicacao).perform).to eq(:lida)
      # Item único não recebe numeração: numerar sugeriria que existe um segundo.
      expect(publicacao.reload.leitura_midia).to eq('Promoção de agosto')
    end

    # Vídeo dentro de carrossel é caso real, e o leitor precisa saber o tipo para escolher
    # entre visão direta e extração de quadros.
    it 'repassa o tipo de cada item ao leitor' do
      stub_media(media_type: 'CAROUSEL_ALBUM', filhos: [
                   { id: '1', media_type: 'VIDEO', media_url: 'https://cdn/1.mp4' }
                 ])
      leitor = instance_double(Spx::Social::LeitorDeMidia, perform: 'texto do video')
      allow(Spx::Social::LeitorDeMidia).to receive(:new).and_return(leitor)

      described_class.new(publicacao: publicacao).perform

      expect(Spx::Social::LeitorDeMidia).to have_received(:new)
        .with(hash_including(tipo: 'VIDEO', url: 'https://cdn/1.mp4'))
    end

    it 'descarta item sem texto legível em vez de poluir o contexto' do
      stub_media(media_type: 'CAROUSEL_ALBUM', filhos: [
                   { id: '1', media_type: 'IMAGE', media_url: 'https://cdn/1.jpg' },
                   { id: '2', media_type: 'IMAGE', media_url: 'https://cdn/2.jpg' }
                 ])
      leitor_devolve('sem texto legível', 'Arroz 5kg por R$ 24,90')

      described_class.new(publicacao: publicacao).perform

      expect(publicacao.reload.leitura_midia).not_to include('sem texto')
      expect(publicacao.leitura_midia).to include('Arroz')
    end

    # Encarte não muda depois de publicado: reler é queimar visão à toa.
    it 'não relê publicação lida há pouco' do
      publicacao.update!(lida_em: 1.hour.ago, leitura_midia: 'ja lido')

      expect(described_class.new(publicacao: publicacao).perform).to eq(:recente)
    end

    it 'marca como lida mesmo quando nada tinha texto, para não reler em loop' do
      stub_media(media_type: 'IMAGE')
      leitor_devolve(nil)

      expect(described_class.new(publicacao: publicacao).perform).to eq(:sem_texto)
      expect(publicacao.reload.lida_em).to be_present
    end

    it 'não derruba nada quando a Graph recusa' do
      stub_request(:get, /graph\.instagram\.com/).to_return(status: 400, body: '{}')

      expect(described_class.new(publicacao: publicacao).perform).to eq(:sem_midia)
    end
  end
end
