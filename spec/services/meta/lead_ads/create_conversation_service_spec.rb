require 'rails_helper'

RSpec.describe Meta::LeadAds::CreateConversationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def hook_with(settings)
    create(:integrations_hook, account: account,
                               app_id: 'meta_lead_ads',
                               settings: { 'target_inbox_id' => inbox.id }.merge(settings))
  end

  def lead_with(attrs)
    { leadgen_id: '1', phone_number: '+5566999990000', full_name: 'Maria' }.merge(attrs)
  end

  def service(hook:, lead:)
    described_class.new(hook: hook, lead: lead)
  end

  describe 'código do imóvel a partir do nome do anúncio' do
    # Os 7 nomes de anúncio distintos que a campanha de formulário realmente produziu
    # (16 leads, nenhum com retailer_item_id — formulário não tem catálogo).
    real_ad_names = {
      'IMÓVEL 9817 - TELHADO APARENTE' => '9817',
      '9817' => '9817',
      'IMÓVEL 9629 - PLATIBANDA' => '9629',
      'IMÓVEL 9621' => '9621',
      'IMÓVEL 9502 - MOBILIADO' => '9502',
      'IMÓVEL 7275' => '7275',
      '7275' => '7275'
    }

    # Nome de anúncio é cheio de número que não é código de imóvel. Um match aqui manda o
    # lead pro imóvel errado — ou pior, abre com a foto de um imóvel que ele nunca viu.
    nao_e_codigo = [
      'CASAS 300-900K',
      '[FORMS] - PACAEMBU',
      'RMKT VENDAS 2026',
      'Casas a partir de 250 mil',
      'APTO 2 QUARTOS - ENTREGA 2027',
      'IMÓVEL PRONTO PARA MORAR 2026',
      'Campanha 01/2026',
      'IMÓVEL DE 3 QUARTOS',
      ''
    ]

    context 'com o hook configurado para ler o nome do anúncio' do
      let(:hook) { hook_with('imovel_codigo_from_ad_name' => true) }

      real_ad_names.each do |ad_name, expected|
        it "extrai #{expected.inspect} de #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to eq(expected)
        end
      end

      nao_e_codigo.each do |ad_name|
        it "não extrai código de #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to be_nil
        end
      end

      it 'aceita o marcador em minúscula e sem acento' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'imovel 9817 - telhado'))
        expect(svc.send(:imovel_codigo)).to eq('9817')
      end

      it 'aceita "cód" como marcador' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'Casa nova (cód 5194)'))
        expect(svc.send(:imovel_codigo)).to eq('5194')
      end

      it 'dá precedência ao retailer_item_id do catálogo' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'IMÓVEL 9817', retailer_item_id: '7686'))
        expect(svc.send(:imovel_codigo)).to eq('7686')
      end
    end

    context 'sem o hook configurado (default de toda conta)' do
      let(:hook) { hook_with({}) }

      real_ad_names.each_key do |ad_name|
        it "ignora o nome do anúncio #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to be_nil
        end
      end

      it 'segue usando o retailer_item_id do catálogo' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'IMÓVEL 9817', retailer_item_id: '7686'))
        expect(svc.send(:imovel_codigo)).to eq('7686')
      end
    end

    context 'quando o hook liga a leitura por override de campanha' do
      let(:hook) do
        hook_with('campaign_overrides' => { '120243133255210544' => { 'imovel_codigo_from_ad_name' => 'true' } })
      end

      it 'lê o nome do anúncio na campanha do override' do
        lead = lead_with(ad_name: 'IMÓVEL 9502 - MOBILIADO', campaign_id: '120243133255210544')
        expect(service(hook: hook, lead: lead).send(:imovel_codigo)).to eq('9502')
      end

      it 'ignora o nome do anúncio nas demais campanhas do mesmo hook' do
        lead = lead_with(ad_name: 'IMÓVEL 9502 - MOBILIADO', campaign_id: '999')
        expect(service(hook: hook, lead: lead).send(:imovel_codigo)).to be_nil
      end
    end

    it 'não busca no Vista quando não há código' do
      hook = hook_with('imovel_codigo_from_ad_name' => true)
      svc = service(hook: hook, lead: lead_with(ad_name: 'CASAS 300-900K'))
      expect(svc).not_to receive(:vista_get)
      expect(svc.send(:imovel_info)).to be_nil
    end
  end

  describe '#initial_message_already_sent?' do
    let(:hook) { hook_with({}) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:svc) { service(hook: hook, lead: lead_with({})) }

    it 'é falso numa conversa sem a abertura' do
      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end

    # A regressão: `content_attributes` é jsonb na tabela mas o modelo grava uma STRING JSON
    # (store coder: JSON), então a consulta antiga (`@>`) nunca casava e a abertura era reenviada.
    it 'é verdadeiro depois da abertura, apesar da dupla serialização' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { meta_lead_ads_initial: true })

      expect(svc.send(:initial_message_already_sent?, conversation)).to be true
    end

    it 'ignora mensagem com outros content_attributes' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { nps_survey: true })

      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end

    it 'não enxerga a abertura de outra conversa' do
      outra = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: outra,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { meta_lead_ads_initial: true })

      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end
  end

  describe 'idempotência da abertura' do
    let(:hook) { hook_with('initial_message_template' => 'Olá {{first_name}}!') }
    let(:lead) { lead_with(full_name: 'Maria Silva') }

    def aberturas(conversation)
      conversation.messages.select { |m| m.content_attributes['meta_lead_ads_initial'] }
    end

    it 'não reenvia a abertura no redelivery do webhook' do
      conversation = service(hook: hook, lead: lead).perform
      expect(aberturas(conversation).size).to eq(1)

      again = service(hook: hook, lead: lead).perform
      expect(again.id).to eq(conversation.id)
      expect(aberturas(again.reload).size).to eq(1)
    end
  end
end
