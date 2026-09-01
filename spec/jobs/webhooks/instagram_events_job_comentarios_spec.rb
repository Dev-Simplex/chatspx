require 'rails_helper'

# Comentário público — o caminho que entra por `changes`, e não por `messaging`.
#
# Até 24/08/2026 este caminho não existia: `test_event?` classificava QUALQUER entry com
# `changes` como evento de teste do painel da Meta, e comentário real morria ali sem rastro.
describe Webhooks::InstagramEventsJob do
  subject(:instagram_webhook) { described_class }

  let!(:account) { create(:account) }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: '17841468839878751') }
  let!(:inbox) { channel.inbox }

  before do
    stub_request(:get, %r{https://graph\.instagram\.com/v22\.0/18103036610158975})
      .to_return(
        status: 200,
        body: {
          caption: 'Promoção de agosto em todas as unidades',
          permalink: 'https://www.instagram.com/reel/abc123/',
          media_product_type: 'REELS',
          thumbnail_url: 'https://cdn.example/thumb.jpg',
          timestamp: '2026-08-23T12:00:00+0000',
          like_count: 218,
          comments_count: 12
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe 'comentário de terceiro' do
    it 'grava o comentário com autor, texto e publicação' do
      evento = build(:instagram_comment_event).with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])

      comentario = Spx::Social::Comentario.last
      expect(comentario.account_id).to eq account.id
      expect(comentario.inbox_id).to eq inbox.id
      expect(comentario.external_id).to eq '18403150897094528'
      expect(comentario.autor_username).to eq 'daynomergpescaria'
      expect(comentario.texto).to eq 'No domingo que horas abre a loja'
      expect(comentario.proprio).to be false
      expect(comentario.comentado_em).to eq Time.zone.at(1_787_522_739)
    end

    it 'guarda o payload cru, porque a Meta omite campo em silêncio' do
      evento = build(:instagram_comment_event).with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])

      expect(Spx::Social::Comentario.last.payload['from']['username']).to eq 'daynomergpescaria'
    end

    it 'resolve a publicação e busca legenda e permalink na Graph' do
      evento = build(:instagram_comment_event).with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])

      publicacao = Spx::Social::Comentario.last.publicacao
      expect(publicacao.external_id).to eq '18103036610158975'
      expect(publicacao.tipo).to eq 'REELS'
      expect(publicacao.legenda).to eq 'Promoção de agosto em todas as unidades'
      expect(publicacao.permalink).to eq 'https://www.instagram.com/reel/abc123/'
      expect(publicacao.metricas['like_count']).to eq 218
      expect(publicacao).to be_sincronizada
    end

    # Medido na .232: 51 entregas para 39 comentários distintos em 7 dias. A Meta reentrega.
    it 'não duplica quando a Meta reentrega o mesmo comentário' do
      evento = build(:instagram_comment_event).with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])
      instagram_webhook.perform_now(evento[:entry])

      expect(Spx::Social::Comentario.count).to eq 1
      expect(Spx::Social::Publicacao.count).to eq 1
    end

    it 'não refaz a chamada à Graph pela segunda pessoa que comenta na mesma publicação' do
      primeiro = build(:instagram_comment_event, comment_id: 'c1').with_indifferent_access
      segundo = build(:instagram_comment_event, comment_id: 'c2').with_indifferent_access

      instagram_webhook.perform_now(primeiro[:entry])
      instagram_webhook.perform_now(segundo[:entry])

      expect(a_request(:get, %r{https://graph\.instagram\.com/v22\.0/18103036610158975})).to have_been_made.once
    end
  end

  describe 'comentário da própria conta' do
    # 22 das 51 entregas medidas eram da própria @bigstoreutilidades: o webhook devolve as
    # respostas que o time publica. Sem esta marca, um agente responderia à própria resposta.
    it 'grava marcado como próprio' do
      evento = build(
        :instagram_comment_event,
        author_id: '17841468839878751',
        author_username: 'bigstoreutilidades',
        text: '@cliente oie, bom dia 😃'
      ).with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])

      comentario = Spx::Social::Comentario.last
      expect(comentario.proprio).to be true
      expect(Spx::Social::Comentario.de_terceiros).to be_empty
    end
  end

  # Pego em execução ao vivo em 25/08: o CDN da Meta devolve `thumbnail_url` com assinatura e
  # expiração, muito acima dos 255 de um `string`. O `update!` estourava no meio da captura e
  # a exceção subia, MATANDO o gatilho da IA — o comentário ficava gravado e ninguém respondia.
  describe 'URL de mídia muito longa' do
    let(:url_gigante) { "https://cdn.example/#{'a' * 900}.jpg" }

    before do
      stub_request(:get, %r{https://graph\.instagram\.com/v22\.0/18103036610158975})
        .to_return(status: 200,
                   body: { caption: 'Promoção', thumbnail_url: url_gigante, permalink: url_gigante }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'grava o comentário mesmo assim' do
      evento = build(:instagram_comment_event).with_indifferent_access

      expect { instagram_webhook.perform_now(evento[:entry]) }.not_to raise_error
      expect(Spx::Social::Comentario.count).to eq(1)
    end

    it 'não deixa de acordar a IA por causa da publicação' do
      evento = build(:instagram_comment_event).with_indifferent_access

      expect { instagram_webhook.perform_now(evento[:entry]) }
        .to have_enqueued_job(Spx::Social::ResponderComentarioComIaJob)
    end
  end

  describe 'gatilho da IA' do
    it 'acorda a IA no comentário novo' do
      evento = build(:instagram_comment_event).with_indifferent_access

      expect { instagram_webhook.perform_now(evento[:entry]) }
        .to have_enqueued_job(Spx::Social::ResponderComentarioComIaJob)
    end

    # A Meta reentrega: 51 entregas para 39 comentários em 7 dias. Sem esta guarda, cada
    # reentrega geraria outra resposta — e a privada é uma por comentário, sem segunda chance.
    it 'não acorda de novo na reentrega do mesmo comentário' do
      evento = build(:instagram_comment_event).with_indifferent_access
      instagram_webhook.perform_now(evento[:entry])

      expect { instagram_webhook.perform_now(evento[:entry]) }
        .not_to have_enqueued_job(Spx::Social::ResponderComentarioComIaJob)
    end

    it 'não acorda a IA no comentário da própria conta' do
      evento = build(:instagram_comment_event, author_id: '17841468839878751',
                                               author_username: 'bigstoreutilidades').with_indifferent_access

      expect { instagram_webhook.perform_now(evento[:entry]) }
        .not_to have_enqueued_job(Spx::Social::ResponderComentarioComIaJob)
    end
  end

  describe 'campo desconhecido' do
    it 'ignora sem estourar e sem gravar nada' do
      evento = build(:instagram_comment_event, field: 'live_comments').with_indifferent_access

      expect { instagram_webhook.perform_now(evento[:entry]) }.not_to raise_error
      expect(Spx::Social::Comentario.count).to eq 0
    end
  end

  describe 'conta desconhecida' do
    it 'ignora comentário de uma conta de Instagram que não é canal aqui' do
      evento = build(:instagram_comment_event, ig_account_id: 'conta-que-nao-existe').with_indifferent_access

      instagram_webhook.perform_now(evento[:entry])

      expect(Spx::Social::Comentario.count).to eq 0
    end
  end

  describe 'evento de teste do painel da Meta' do
    # A regressão que mais importa evitar: o payload de teste TAMBÉM chega em `changes`. Ele se
    # distingue por `entry.id == "0"`, e tem que continuar indo pro TestEventService.
    it 'continua sendo tratado como teste, não como comentário' do
      evento = build(:instagram_test_event).with_indifferent_access

      expect(Instagram::TestEventService).to receive(:new).and_call_original
      instagram_webhook.perform_now(evento[:entry])

      expect(Spx::Social::Comentario.count).to eq 0
    end
  end
end
