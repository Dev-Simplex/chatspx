require 'rails_helper'

# Bloco 4.14 — DE ONDE VEM O STATUS QUE VAI PARA O LOG.
#
# Ate o bloco 1.13, Webhooks::Trigger#execute engolia a excecao e o job terminava com
# sucesso: o webhook REPORTAVA entrega que nao aconteceu. Um log alimentado por "o job nao
# explodiu" gravaria "entregue" para exatamente essas entregas.
#
# Estes exemplos existem para provar que a fonte e outra: o registro nasce dentro do
# Trigger, nos dois pontos em que ele SABE o resultado da requisicao.
RSpec.describe Webhooks::Trigger do
  let(:account) { create(:account) }
  let(:webhook) do
    create(:webhook, account: account, url: 'https://destino.exemplo.com/h',
                     subscriptions: ['conversation_created'])
  end
  let(:payload) { { event: 'conversation_created', id: 7 } }
  let(:delivery) { described_class::Delivery.new(id: 'entrega-1', webhook_id: webhook.id) }

  def executar
    described_class.execute(webhook.url, payload, :account_webhook, secret: webhook.secret, delivery: delivery)
  end

  def registro
    webhook.webhook_deliveries.find_by(delivery_id: 'entrega-1')
  end

  it 'grava entregue quando a requisicao realmente passou' do
    allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))

    executar

    expect(registro.status).to eq('delivered')
    expect(registro.delivered_at).to be_present
    expect(registro.event).to eq('conversation_created')
  end

  # O caso que o 1.13 corrigiu: 500 e transitorio, a excecao SOBE e o job reentrega. O
  # registro tem de dizer "falhou", nao "entregue".
  it 'grava falhou num 500, mesmo com a excecao subindo' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))

    expect { executar }.to raise_error(SafeFetch::HttpError)

    expect(registro.status).to eq('failed')
    expect(registro.http_status).to eq(500)
    expect(registro.error_message).to eq('500 Internal Server Error')
    expect(registro.delivered_at).to be_nil
  end

  # A ARMADILHA. Num erro permanente (404) o Trigger NAO levanta: ele chama handle_failure
  # e retorna normalmente, entao o JOB TERMINA COM SUCESSO. Quem lesse o resultado do job
  # gravaria "entregue" para uma entrega que o destino recusou.
  it 'grava falhou num 404, mesmo o job terminando com sucesso' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

    expect { executar }.not_to raise_error

    expect(registro.status).to eq('failed')
    expect(registro.http_status).to eq(404)
  end

  it 'grava falhou quando o filtro SSRF barra o destino' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::UnsafeUrlError.new('Blocked private address'))

    executar

    expect(registro.status).to eq('failed')
    expect(registro.error_message).to eq('Blocked private address')
  end

  # As cinco tentativas do 1.13 sao a MESMA entrega, e o log tem de refletir isso: uma
  # linha por delivery_id, atualizada, e nao cinco linhas dizendo que houve cinco entregas.
  it 'a reentrega atualiza a mesma linha em vez de criar outra' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error'))
    expect { executar }.to raise_error(SafeFetch::HttpError)

    allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))
    executar

    expect(webhook.webhook_deliveries.where(delivery_id: 'entrega-1').count).to eq(1)
    expect(registro.status).to eq('delivered')
  end

  describe 'quando nao ha registro Webhook por tras' do
    let(:delivery) { described_class::Delivery.new(id: 'entrega-1') }

    it 'entrega normalmente e nao grava nada' do
      allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))

      expect { executar }.not_to change(WebhookDelivery, :count)
    end
  end

  it 'falha ao gravar o log NAO derruba a entrega' do
    allow(SafeFetch).to receive(:fetch).and_yield(instance_double(SafeFetch::Result))
    allow(Webhook).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid, 'banco fora')

    expect { executar }.not_to raise_error
  end
end
