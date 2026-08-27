require 'rails_helper'

RSpec.describe Meta::LeadAds::CreateConversationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  # settings_json_schema (config/integration/apps.yml) exige os 5 campos do formulário.
  # As chaves de operador (campaign_overrides, imovel_*) passam por additionalProperties.
  def hook_with(settings)
    create(:integrations_hook, account: account,
                               app_id: 'meta_lead_ads',
                               settings: {
                                 'page_id' => '539594042748152',
                                 'verify_token' => 'verify',
                                 'app_secret' => 'secret',
                                 'page_access_token' => 'token',
                                 'target_inbox_id' => inbox.id
                               }.merge(settings))
  end

  def lead_with(attrs)
    { leadgen_id: '1', phone_number: '+5566999990000', full_name: 'Maria' }.merge(attrs)
  end

  def service(hook:, lead:)
    described_class.new(hook: hook, lead: lead)
  end

  describe 'resolving the imovel code' do
    # Os 7 nomes de anuncio distintos que a campanha de formulario realmente produziu
    # (16 leads, nenhum com retailer_item_id — formulario nao tem catalogo).
    real_ad_names = {
      'IMÓVEL 9817 - TELHADO APARENTE' => '9817',
      '9817' => '9817',
      'IMÓVEL 9629 - PLATIBANDA' => '9629',
      'IMÓVEL 9621' => '9621',
      'IMÓVEL 9502 - MOBILIADO' => '9502',
      'IMÓVEL 7275' => '7275',
      '7275' => '7275'
    }

    # Nome de anuncio e cheio de numero que nao e codigo de imovel. Um match aqui manda o
    # lead pro imovel errado — ou pior, abre com a foto de um imovel que ele nunca viu.
    not_a_code = [
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

    context 'when the hook enables reading the ad name' do
      let(:hook) { hook_with('imovel_codigo_from_ad_name' => true) }

      real_ad_names.each do |ad_name, expected|
        it "extracts #{expected.inspect} from #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to eq(expected)
        end
      end

      not_a_code.each do |ad_name|
        it "extracts nothing from #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to be_nil
        end
      end

      it 'accepts the marker lowercased and unaccented' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'imovel 9817 - telhado'))
        expect(svc.send(:imovel_codigo)).to eq('9817')
      end

      it 'accepts "cód" as a marker' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'Casa nova (cód 5194)'))
        expect(svc.send(:imovel_codigo)).to eq('5194')
      end

      it 'gives precedence to the catalog retailer_item_id' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'IMÓVEL 9817', retailer_item_id: '7686'))
        expect(svc.send(:imovel_codigo)).to eq('7686')
      end

      it 'does not reach the Vista API when there is no code' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'CASAS 300-900K'))
        expect(svc).not_to receive(:vista_get)
        expect(svc.send(:imovel_info)).to be_nil
      end
    end

    context 'without the hook setting (the default for every account)' do
      let(:hook) { hook_with({}) }

      real_ad_names.each_key do |ad_name|
        it "ignores the ad name #{ad_name.inspect}" do
          svc = service(hook: hook, lead: lead_with(ad_name: ad_name))
          expect(svc.send(:imovel_codigo)).to be_nil
        end
      end

      it 'still uses the catalog retailer_item_id' do
        svc = service(hook: hook, lead: lead_with(ad_name: 'IMÓVEL 9817', retailer_item_id: '7686'))
        expect(svc.send(:imovel_codigo)).to eq('7686')
      end
    end

    context 'when the setting comes from a campaign override' do
      let(:hook) do
        hook_with('campaign_overrides' => { '120243133255210544' => { 'imovel_codigo_from_ad_name' => 'true' } })
      end

      it 'reads the ad name on the overridden campaign' do
        lead = lead_with(ad_name: 'IMÓVEL 9502 - MOBILIADO', campaign_id: '120243133255210544')
        expect(service(hook: hook, lead: lead).send(:imovel_codigo)).to eq('9502')
      end

      it 'ignores the ad name on the other campaigns of the same hook' do
        lead = lead_with(ad_name: 'IMÓVEL 9502 - MOBILIADO', campaign_id: '999')
        expect(service(hook: hook, lead: lead).send(:imovel_codigo)).to be_nil
      end
    end
  end

  describe '#initial_message_already_sent?' do
    let(:hook) { hook_with({}) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:svc) { service(hook: hook, lead: lead_with({})) }

    def initial_message_on(conv)
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { meta_lead_ads_initial: true })
    end

    it 'is false on a conversation without the opener' do
      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end

    # A regressao: content_attributes e jsonb NA TABELA mas o modelo grava uma STRING JSON
    # (store coder: JSON), entao a consulta antiga (`@>`) nunca casava e a abertura era reenviada.
    it 'is true after the opener, despite the double serialization' do
      initial_message_on(conversation)

      expect(svc.send(:initial_message_already_sent?, conversation)).to be true
    end

    it 'ignores messages carrying other content_attributes' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { nps_survey: true })

      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end

    it 'does not see the opener of another conversation' do
      initial_message_on(create(:conversation, account: account, inbox: inbox))

      expect(svc.send(:initial_message_already_sent?, conversation)).to be false
    end
  end

  describe 'opener idempotency' do
    let(:hook) { hook_with('initial_message_template' => 'Olá {{first_name}}!') }
    let(:lead) { lead_with(full_name: 'Maria Silva') }

    def openers(conversation)
      conversation.messages.select { |m| m.content_attributes['meta_lead_ads_initial'] }
    end

    it 'does not resend the opener on a webhook redelivery' do
      conversation = service(hook: hook, lead: lead).perform
      expect(openers(conversation).size).to eq(1)

      again = service(hook: hook, lead: lead).perform
      expect(again.id).to eq(conversation.id)
      expect(openers(again.reload).size).to eq(1)
    end
  end

  # A tela de campanhas oferece `BODY_FIELDS` como as opções para preencher {{1}}, {{2}}...
  # e recusa qualquer outra. Se a lista e o contexto real se separarem, a tela passa a
  # oferecer um campo que renderiza VAZIO — e template com parâmetro vazio a Meta recusa.
  describe 'the lead fields offered to fill the template body' do
    it 'is exactly what the render context provides' do
      contexto = service(hook: hook_with({}), lead: lead_with({})).send(:template_render_context)

      expect(described_class::BODY_FIELDS).to match_array(contexto.keys)
    end
  end
end
