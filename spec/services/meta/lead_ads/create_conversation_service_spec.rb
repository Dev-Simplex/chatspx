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

  describe '#last_initial_message' do
    let(:hook) { hook_with({}) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:svc) { service(hook: hook, lead: lead_with({})) }

    def initial_message_on(conv)
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { meta_lead_ads_initial: true })
    end

    it 'is false on a conversation without the opener' do
      expect(svc.send(:last_initial_message, conversation)).to be_nil
    end

    # A regressao: content_attributes e jsonb NA TABELA mas o modelo grava uma STRING JSON
    # (store coder: JSON), entao a consulta antiga (`@>`) nunca casava e a abertura era reenviada.
    it 'is true after the opener, despite the double serialization' do
      initial_message_on(conversation)

      expect(svc.send(:last_initial_message, conversation)).to be_present
    end

    it 'ignores messages carrying other content_attributes' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Olá!',
                       content_attributes: { nps_survey: true })

      expect(svc.send(:last_initial_message, conversation)).to be_nil
    end

    it 'does not see the opener of another conversation' do
      initial_message_on(create(:conversation, account: account, inbox: inbox))

      expect(svc.send(:last_initial_message, conversation)).to be_nil
    end

    it 'ignores an opener older than the dedup window' do
      travel_to(25.hours.ago) { initial_message_on(conversation) }

      expect(svc.send(:last_initial_message, conversation)).to be_nil
    end

    it 'still sees an opener inside the dedup window' do
      travel_to(23.hours.ago) { initial_message_on(conversation) }

      expect(svc.send(:last_initial_message, conversation)).to be_present
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

    it 'does not resend when the same lead is redelivered minutes later' do
      conversation = service(hook: hook, lead: lead).perform

      travel 10.minutes do
        again = service(hook: hook, lead: lead).perform
        expect(again.id).to eq(conversation.id)
        expect(openers(again.reload).size).to eq(1)
      end
    end

    # O bug de 06/10/2026: conversa reaproveitada que teve abertura meses atras calava o lead novo.
    it 'sends the opener again to a lead returning to an old open conversation' do
      conversation = travel_to(2.months.ago) { service(hook: hook, lead: lead).perform }
      expect(conversation.reload.status).not_to eq('resolved')

      again = service(hook: hook, lead: lead_with(leadgen_id: '2', full_name: 'Maria Silva')).perform
      expect(again.id).to eq(conversation.id)
      expect(openers(again.reload).size).to eq(2)
    end

    it 'reopens an old resolved conversation and sends the opener again' do
      conversation = travel_to(1.month.ago) { service(hook: hook, lead: lead).perform }
      conversation.resolved!

      again = service(hook: hook, lead: lead_with(leadgen_id: '2', full_name: 'Maria Silva')).perform
      expect(again.id).to eq(conversation.id)
      expect(again.reload.status).not_to eq('resolved')
      expect(openers(again).size).to eq(2)
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

  # Cada lead que chega deixa uma linha de atividade na conversa (o cliente não recebe) com a
  # origem e o que aconteceu com a abertura — antes, o único rastro era o log do servidor.
  describe 'lead activity line' do
    let(:account) { create(:account, locale: 'pt_BR') }
    let(:lead) { lead_with(full_name: 'Maria Silva') }

    before { travel_to Time.zone.local(2026, 10, 7, 14, 5) }

    def activities(conversation)
      conversation.reload.messages.where(message_type: :activity).pluck(:content)
    end

    def openers(conversation)
      conversation.messages.select { |m| m.content_attributes['meta_lead_ads_initial'] }
    end

    it 'records the opener as sent' do
      conversation = service(hook: hook_with('initial_message_template' => 'Olá {{first_name}}!'), lead: lead).perform

      expect(activities(conversation)).to eq(['Novo lead por anúncio às 14:05 · abertura enviada'])
    end

    it 'records the cooldown skip with the time of the previous opener' do
      hook = hook_with('initial_message_template' => 'Olá {{first_name}}!')
      conversation = service(hook: hook, lead: lead).perform

      travel 30.minutes
      service(hook: hook, lead: lead).perform

      expect(activities(conversation).last).to eq('Novo lead por anúncio às 14:35 · abertura não enviada: já enviada às 14:05')
    end

    it 'shows the date when the previous opener was on another day' do
      hook = hook_with('initial_message_template' => 'Olá {{first_name}}!', 'initial_message_cooldown_hours' => 48)
      conversation = service(hook: hook, lead: lead).perform

      travel 1.day
      service(hook: hook, lead: lead).perform

      expect(activities(conversation).last).to eq('Novo lead por anúncio às 14:05 · abertura não enviada: já enviada em 07/10 às 14:05')
    end

    it 'records a lead without phone' do
      conversation = service(hook: hook_with({}), lead: lead_with(phone_number: nil, leadgen_id: '9')).perform

      expect(activities(conversation)).to eq(['Novo lead por anúncio às 14:05 · sem telefone: abertura não enviada'])
    end

    it 'records a read-only inbox' do
      inbox.update!(read_only: true)
      conversation = service(hook: hook_with({}), lead: lead).perform

      expect(openers(conversation)).to be_empty
      expect(activities(conversation)).to eq(['Novo lead por anúncio às 14:05 · caixa somente leitura: abertura não enviada'])
    end

    it 'records a form set up without opener' do
      conversation = service(hook: hook_with('skip_initial_message' => true), lead: lead).perform

      expect(activities(conversation)).to eq(['Novo lead por anúncio às 14:05 · formulário configurado sem abertura'])
    end

    it 'names the website as the origin of a site lead' do
      hook = create(:integrations_hook, account: account, app_id: 'site_leads',
                                        settings: { 'shared_secret' => 's3cr3t', 'target_inbox_id' => inbox.id })
      conversation = service(hook: hook, lead: lead).perform

      expect(activities(conversation)).to eq(['Novo lead pelo site às 14:05 · abertura enviada'])
    end
  end

  # A janela de 24 h entre aberturas é o padrão; cada formulário pode pedir outra.
  describe 'opener cooldown per hook' do
    let(:lead) { lead_with(full_name: 'Maria Silva') }

    def openers_after(hook, gap)
      conversation = service(hook: hook, lead: lead).perform
      travel gap do
        service(hook: hook, lead: lead).perform
      end
      conversation.reload.messages.count { |m| m.content_attributes['meta_lead_ads_initial'] }
    end

    def hook_cooldown(value)
      hook_with('initial_message_template' => 'Olá!', 'initial_message_cooldown_hours' => value)
    end

    it 'defaults to 24 hours' do
      expect(openers_after(hook_with('initial_message_template' => 'Olá!'), 23.hours)).to eq(1)
    end

    it 'sends again after the default 24 hours' do
      expect(openers_after(hook_with('initial_message_template' => 'Olá!'), 25.hours)).to eq(2)
    end

    it 'honors a shorter cooldown' do
      expect(openers_after(hook_cooldown(1), 2.hours)).to eq(2)
    end

    it 'honors a longer cooldown' do
      expect(openers_after(hook_cooldown('48'), 30.hours)).to eq(1)
    end

    it 'falls back to 24 hours on a value that is not a number' do
      expect(openers_after(hook_cooldown('abc'), 23.hours)).to eq(1)
    end

    it 'falls back to 24 hours on zero' do
      expect(openers_after(hook_cooldown(0), 23.hours)).to eq(1)
    end
  end

  # Lead novo dentro do cooldown com o cliente conversando com a IA: em vez de template, a IA
  # retoma pelo mesmo caminho da cutucada (ResponseBuilderJob com diretiva).
  describe 'waking the assistant on a new lead inside the cooldown' do
    let(:account) { create(:account, locale: 'pt_BR') }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:hook) { hook_with('initial_message_template' => 'Olá!', 'initial_message_cooldown_hours' => 48) }
    let(:lead) { lead_with(full_name: 'Maria Silva') }
    let!(:conversation) { travel_to(2.hours.ago) { service(hook: hook, lead: lead).perform } }

    def converse(customer_wrote_at)
      conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'Oi, quero saber mais', created_at: customer_wrote_at)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       sender: assistant, content: 'Claro!', created_at: customer_wrote_at + 1.minute)
    end

    def openers
      conversation.reload.messages.count { |m| m.content_attributes['meta_lead_ads_initial'] }
    end

    def new_lead
      service(hook: hook, lead: lead_with(leadgen_id: '2', full_name: 'Maria Silva')).perform
    end

    it 'enqueues the assistant response instead of the template when the window is open' do
      converse(1.hour.ago)

      expect { new_lead }.to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
        .with(conversation, assistant, directive: a_string_including('novo formulário'))
      expect(openers).to eq(1)
      expect(conversation.messages.where(message_type: :activity).last.content).to include('a IA retomou com o novo interesse')
    end

    it 'does not wake the assistant when the customer window is closed' do
      conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)
      travel 30.hours

      expect { new_lead }.not_to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
      expect(openers).to eq(1)
      expect(conversation.messages.where(message_type: :activity).last.content).to include('já enviada')
    end

    it 'does not wake the assistant when the customer last wrote more than 24 hours ago' do
      converse(1.hour.ago)
      travel 25.hours

      expect { new_lead }.not_to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
    end

    it 'does not wake the assistant when a human is assigned' do
      converse(1.hour.ago)
      conversation.update!(assignee: create(:user, account: account, role: :agent))

      expect { new_lead }.not_to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
    end

    it 'does not wake the assistant while its reply to the customer is still pending' do
      converse(1.hour.ago)
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'e o preço?', created_at: 1.minute.ago)

      expect { new_lead }.not_to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
    end
  end
end
