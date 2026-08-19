require 'rails_helper'

# Bloco 4.13 — o filtro por inbox e a assinatura dos caminhos que saiam nus.
RSpec.describe WebhookListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox_a) { create(:inbox, account: account) }
  let(:inbox_b) { create(:inbox, account: account) }
  let(:conversation_a) { create(:conversation, account: account, inbox: inbox_a) }
  let(:event_a) { Events::Base.new('conversation.created', Time.zone.now, { conversation: conversation_a }) }

  def urls_entregues
    entregues = []
    allow(WebhookJob).to receive(:perform_later) { |url, *| entregues << url }
    yield
    entregues
  end

  describe 'filtro por inbox' do
    let!(:preso_a) do
      create(:webhook, account: account, inbox: inbox_a, url: 'https://a.exemplo.com/h',
                       subscriptions: ['conversation_created'])
    end
    let!(:preso_b) do
      create(:webhook, account: account, inbox: inbox_b, url: 'https://b.exemplo.com/h',
                       subscriptions: ['conversation_created'])
    end
    let!(:sem_inbox) do
      create(:webhook, account: account, inbox: nil, url: 'https://tudo.exemplo.com/h',
                       subscriptions: ['conversation_created'])
    end

    it 'entrega so ao webhook da inbox do evento, e ao que nao escolheu inbox' do
      entregues = urls_entregues { listener.conversation_created(event_a) }

      expect(entregues).to contain_exactly(preso_a.url, sem_inbox.url)
    end

    it 'o webhook da outra inbox NAO recebe' do
      entregues = urls_entregues { listener.conversation_created(event_a) }

      expect(entregues).not_to include(preso_b.url)
    end

    it 'sem inbox_id continua recebendo tudo — o comportamento de quem nao preencheu o campo' do
      evento_b = Events::Base.new('conversation.created', Time.zone.now,
                                  { conversation: create(:conversation, account: account, inbox: inbox_b) })

      entregues = urls_entregues { listener.conversation_created(evento_b) }

      expect(entregues).to contain_exactly(preso_b.url, sem_inbox.url)
    end

    # Antes, um webhook com webhook_type inbox_type ficava fora do escopo `account_type` e
    # nao recebia NADA, em silencio. O tipo deixou de decidir a entrega.
    it 'webhook marcado como inbox_type volta a receber' do
      preso_a.update!(webhook_type: :inbox_type)

      entregues = urls_entregues { listener.conversation_created(event_a) }

      expect(entregues).to include(preso_a.url)
    end

    # Contato nao pertence a inbox nenhuma. Quem escolheu uma inbox pediu o que acontece
    # NELA — entregar o resto seria devolver mais do que foi pedido.
    it 'evento sem inbox so vai para quem nao escolheu inbox' do
      contato = create(:contact, account: account)
      evento = Events::Base.new('contact.created', Time.zone.now, { contact: contato, account: account })
      %w[contact_created].each { |e| [preso_a, sem_inbox].each { |w| w.update!(subscriptions: [e]) } }

      entregues = urls_entregues { listener.contact_created(evento) }

      expect(entregues).to eq([sem_inbox.url])
    end
  end

  describe 'unicidade de URL' do
    it 'aceita a mesma URL em inboxes diferentes' do
      create(:webhook, account: account, inbox: inbox_a, url: 'https://mesma.exemplo.com/h',
                       subscriptions: ['conversation_created'])
      segundo = build(:webhook, account: account, inbox: inbox_b, url: 'https://mesma.exemplo.com/h',
                                subscriptions: ['conversation_created'])

      expect(segundo).to be_valid
    end

    it 'continua recusando a mesma URL duas vezes na mesma inbox' do
      create(:webhook, account: account, inbox: inbox_a, url: 'https://mesma.exemplo.com/h',
                       subscriptions: ['conversation_created'])
      duplicado = build(:webhook, account: account, inbox: inbox_a, url: 'https://mesma.exemplo.com/h',
                                  subscriptions: ['conversation_created'])

      expect(duplicado).not_to be_valid
    end

    it 'continua recusando a mesma URL duas vezes sem inbox' do
      create(:webhook, account: account, inbox: nil, url: 'https://mesma.exemplo.com/h',
                       subscriptions: ['conversation_created'])
      duplicado = build(:webhook, account: account, inbox: nil, url: 'https://mesma.exemplo.com/h',
                                  subscriptions: ['conversation_created'])

      expect(duplicado).not_to be_valid
    end
  end
end
