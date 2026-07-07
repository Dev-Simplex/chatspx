require 'rails_helper'

RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }

  after { Current.reset }

  def action(name, params)
    { 'type' => 'action', 'action_name' => name, 'action_params' => params }
  end

  describe '#send_template (gap-BR P0)' do
    let(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
    let(:template) { { 'name' => 'test_no_params_template', 'language' => 'en', 'content' => 'Olá!', 'processed_params' => {} } }

    it 'creates an outgoing message carrying template_params for an approved template' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('send_template', [template])) }.to change(Message, :count).by(1)
      expect(Message.last.additional_attributes['template_params']).to include('name' => 'test_no_params_template', 'language' => 'en')
    end

    it 'carries the flow_id anti-loop marker in automation mode' do
      described_class.new(flow: flow, conversation: conversation).execute(action('send_template', [template]))
      expect(Message.last.content_attributes['flow_id']).to eq(flow.id)
    end

    it 'is a silent no-op when the template is not approved (padrão add_sla)' do
      service = described_class.new(flow: flow, conversation: conversation)
      unknown = template.merge('name' => 'nonexistent_template')
      expect { service.execute(action('send_template', [unknown])) }.not_to change(Message, :count)
    end

    it 'is a silent no-op when the inbox is not whatsapp_cloud' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      service = described_class.new(flow: flow, conversation: other)
      expect { service.execute(action('send_template', [template])) }.not_to change(Message, :count)
    end

    it 'works when no display content is provided (template-only)' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('send_template', [template.except('content')])) }.to change(Message, :count).by(1)
    end

    it 'does not send in manual mode either — pipeline stays the same, authored by the actor' do
      agent = create(:user, account: account)
      service = described_class.new(flow: flow, conversation: conversation, actor: agent)
      service.execute(action('send_template', [template]))
      expect(Message.last.sender).to eq(agent)
      expect(Message.last.content_attributes['flow_id']).to be_nil
    end
  end

  describe '#set_attribute' do
    let(:conversation) { create(:conversation, account: account) }

    it 'writes a custom attribute on the conversation' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'key' => 'lead_score', 'value' => 'quente' }]))
      expect(conversation.reload.custom_attributes['lead_score']).to eq('quente')
    end

    it 'writes an additional attribute when store is additional' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute',
                                     [{ 'target' => 'conversation', 'store' => 'additional', 'key' => 'origem', 'value' => 'anuncio' }]))
      expect(conversation.reload.additional_attributes['origem']).to eq('anuncio')
    end

    it 'writes on the contact when target is contact' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'contact', 'key' => 'vip', 'value' => 'true' }]))
      expect(conversation.contact.reload.custom_attributes['vip']).to eq('true')
    end

    it 'resolves Liquid in the value' do
      conversation.contact.update!(name: 'Maria')
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'key' => 'saudacao', 'value' => 'Oi {{contact.name}}' }]))
      expect(conversation.reload.custom_attributes['saudacao']).to eq('Oi Maria')
    end

    it 'is a no-op when key is blank' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'value' => 'x' }]))
      expect(conversation.reload.custom_attributes).to eq({})
    end
  end

  describe '#move_funnel_stage (expõe o Kanban ao motor)' do
    let(:conversation) { create(:conversation, account: account) }
    let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
    let(:stage_lead) { FunnelStage.create!(funnel: funnel, name: 'Lead', position: 0) }
    let(:stage_won) { FunnelStage.create!(funnel: funnel, name: 'Ganho', position: 1) }

    # A conta nasce com um funil padrão (Account#create_default_funnel) e toda conversa é
    # auto-colocada nele (Conversation#add_to_appropriate_funnel, after_create_commit).
    # Limpamos essa colocação incidental para isolar os cenários abaixo.
    before { conversation.funnel_items.destroy_all }

    def move(params)
      described_class.new(flow: flow, conversation: conversation).execute(action('move_funnel_stage', [params]))
    end

    it 'moves an existing funnel_item to the target stage via FunnelItems::MoveService' do
      item = FunnelItem.create!(conversation: conversation, funnel: funnel, funnel_stage: stage_lead)
      move({ 'funnel_id' => funnel.id, 'stage_id' => stage_won.id })
      expect(item.reload.funnel_stage_id).to eq(stage_won.id)
    end

    it 'resolves the funnel implicitly from the conversation when no funnel_id is given' do
      item = FunnelItem.create!(conversation: conversation, funnel: funnel, funnel_stage: stage_lead)
      move({ 'stage_id' => stage_won.id })
      expect(item.reload.funnel_stage_id).to eq(stage_won.id)
    end

    it 'accepts stage_id under the shorthand key "stage"' do
      item = FunnelItem.create!(conversation: conversation, funnel: funnel, funnel_stage: stage_lead)
      move({ 'funnel_id' => funnel.id, 'stage' => stage_won.id })
      expect(item.reload.funnel_stage_id).to eq(stage_won.id)
    end

    it 'is a safe no-op (never creates a placement) when the conversation is in no funnel' do
      stage_won # ensure the funnel/stage exist, but the conversation is NOT placed in it
      expect { move({ 'funnel_id' => funnel.id, 'stage_id' => stage_won.id }) }.not_to change(FunnelItem, :count)
      expect(conversation.reload.funnel_items.where(funnel_id: funnel.id)).to be_empty
    end

    it 'is a no-op when the target stage does not exist' do
      item = FunnelItem.create!(conversation: conversation, funnel: funnel, funnel_stage: stage_lead)
      move({ 'funnel_id' => funnel.id, 'stage_id' => 0 })
      expect(item.reload.funnel_stage_id).to eq(stage_lead.id)
    end

    it 'is a no-op when stage_id is blank' do
      item = FunnelItem.create!(conversation: conversation, funnel: funnel, funnel_stage: stage_lead)
      move({ 'funnel_id' => funnel.id })
      expect(item.reload.funnel_stage_id).to eq(stage_lead.id)
    end
  end

  describe '#call_macro (roda uma macro sobre a conversa)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'runs the macro actions over the conversation (reuso do vocabulário de ações)' do
      macro = create(:macro, account: account, actions: [{ 'action_name' => 'add_label', 'action_params' => %w[quente] }])
      described_class.new(flow: flow, conversation: conversation).execute(action('call_macro', [macro.id]))
      expect(conversation.reload.label_list).to include('quente')
    end

    it 'marks macro-sent messages with the flow_id anti-loop marker (prevents macro→flow→macro)' do
      macro = create(:macro, account: account, actions: [{ 'action_name' => 'send_message', 'action_params' => ['Olá'] }])
      described_class.new(flow: flow, conversation: conversation).execute(action('call_macro', [macro.id]))
      expect(Message.last.content_attributes['flow_id']).to eq(flow.id)
    end

    it 'respects the anti-recursion depth guard (no-op above MAX_DEPTH)' do
      macro = create(:macro, account: account, actions: [{ 'action_name' => 'add_label', 'action_params' => %w[loop] }])
      service = described_class.new(flow: flow, conversation: conversation)
      Current.flow_depth = Flows::RunnerService::MAX_DEPTH + 1
      service.execute(action('call_macro', [macro.id]))
      expect(conversation.reload.label_list).not_to include('loop')
    end

    it 'restores flow_depth after running (balanced counter)' do
      macro = create(:macro, account: account, actions: [{ 'action_name' => 'add_label', 'action_params' => %w[x] }])
      service = described_class.new(flow: flow, conversation: conversation)
      Current.flow_depth = 1
      service.execute(action('call_macro', [macro.id]))
      expect(Current.flow_depth).to eq(1)
    end

    it 'is a no-op for an unknown macro id' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('call_macro', [0])) }.not_to change(Message, :count)
    end
  end

  describe '#send_csat (dispara a pesquisa CSAT via CsatSurveyService)' do
    let(:inbox) { create(:inbox, account: account, csat_survey_enabled: true) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }

    it 'creates an input_csat message reusing the product CSAT path' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('send_csat', [])) }
        .to change { conversation.reload.messages.where(content_type: :input_csat).count }.by(1)
    end

    it 'inherits the product guard: no-op when CSAT is disabled on the inbox' do
      other_inbox = create(:inbox, account: account, csat_survey_enabled: false)
      other = create(:conversation, account: account, inbox: other_inbox, status: :resolved)
      service = described_class.new(flow: flow, conversation: other)
      expect { service.execute(action('send_csat', [])) }
        .not_to(change { other.reload.messages.where(content_type: :input_csat).count })
    end

    it 'inherits the product dedup guard: does not send the CSAT twice' do
      service = described_class.new(flow: flow, conversation: conversation)
      service.execute(action('send_csat', []))
      expect { service.execute(action('send_csat', [])) }
        .not_to(change { conversation.reload.messages.where(content_type: :input_csat).count })
    end
  end
end
