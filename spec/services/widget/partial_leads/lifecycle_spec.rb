# frozen_string_literal: true

require 'rails_helper'

# 4.18 — o CICLO do lead incompleto: configuracao com padrao declarado, materializacao do
# abandono no painel, o relatorio que responde "quantos leads perdemos e onde" e a
# retencao (LGPD) que apaga o registro parcial de quem nao concluiu.
# rubocop:disable RSpec/DescribeClass -- o assunto e o CICLO, que atravessa quatro classes
# (Settings, MaterializeService, SweepJob, Report). Descrever uma delas no topo obrigaria a
# quatro arquivos que repetiriam o mesmo cenario de visitante; o `describe` interno ja nomeia
# a classe de cada bloco.
RSpec.describe 'Widget::PartialLeads — o ciclo do lead incompleto' do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  def enable_capture!(extra = {})
    account.update!(internal_attributes: account.internal_attributes.merge(
      { 'partial_lead_capture_enabled' => true }.merge(extra)
    ))
  end

  # A sessao do visitante e o `source_id` do ContactInbox, como no widget real.
  def visitor_session(email: 'walisson@empresa.com.br')
    contact = create(:contact, account: account, email: nil, phone_number: nil)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    lead = create(:widget_partial_lead, account: account, inbox: inbox,
                                        session_id: contact_inbox.source_id,
                                        answers: { 'fullName' => 'Walisson', 'emailAddress' => email }.compact,
                                        step_reached: 3, step_key: 'phoneNumber',
                                        last_answered_at: 30.minutes.ago)
    [contact.reload, lead]
  end

  describe Widget::PartialLeads::Settings do
    it 'nasce DESLIGADA — dado de quem nao concluiu nao se guarda por padrao (LGPD)' do
      expect(described_class.new(account).enabled?).to be(false)
    end

    it 'declara os padroes: 5 minutos de abandono, 30 dias de retencao, etiqueta lead-incompleto' do
      settings = described_class.new(account)

      expect(settings.abandon_after_minutes).to eq(5)
      expect(settings.retention_days).to eq(30)
      expect(settings.label).to eq('lead-incompleto')
    end

    it 'aceita a configuracao da conta' do
      enable_capture!('partial_lead_abandon_after_minutes' => 15, 'partial_lead_retention_days' => 7,
                      'partial_lead_label' => 'perdido')
      settings = described_class.new(account.reload)

      expect(settings).to be_enabled
      expect(settings.abandon_after_minutes).to eq(15)
      expect(settings.retention_days).to eq(7)
      expect(settings.label).to eq('perdido')
    end

    it 'cai no padrao declarado diante de valor torto, em vez de virar retencao infinita' do
      enable_capture!('partial_lead_retention_days' => 'para sempre', 'partial_lead_abandon_after_minutes' => -3)
      settings = described_class.new(account.reload)

      expect(settings.retention_days).to eq(30)
      expect(settings.abandon_after_minutes).to eq(1) # o minimo, nao o negativo
    end

    it 'etiqueta vazia desliga a etiqueta sem desligar a captura' do
      enable_capture!('partial_lead_label' => '  ')

      expect(described_class.new(account.reload).label).to eq('')
    end
  end

  describe Widget::PartialLeads::MaterializeService do
    before { enable_capture! }

    it 'materializa o contato marcado como INCOMPLETO, com a etapa em que parou' do
      _contact, lead = visitor_session

      materializado = described_class.new(lead).perform

      expect(materializado.email).to eq('walisson@empresa.com.br')
      expect(materializado.custom_attributes['widget_lead_incomplete']).to be(true)
      expect(materializado.custom_attributes['widget_lead_step']).to eq(3)
      expect(materializado.custom_attributes['widget_lead_step_name']).to eq('phoneNumber')
      expect(materializado.label_list).to include('lead-incompleto')
      expect(lead.reload.contact_id).to eq(materializado.id)
      expect(lead.abandoned_at).to be_present
    end

    # A METADE MAIS IMPORTANTE DO ACEITE: o lead incompleto NAO e uma conversa.
    it 'NAO cria conversa — e por isso nao dispara automacao, campanha nem webhook de conversa' do
      _contact, lead = visitor_session

      expect { described_class.new(lead).perform }.not_to change(Conversation, :count)
      expect(Conversation.where(inbox_id: inbox.id)).to be_empty
    end

    it 'nao materializa nada sem canal de contato' do
      contact = create(:contact, account: account, email: nil, phone_number: nil)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      lead = create(:widget_partial_lead, account: account, inbox: inbox,
                                          session_id: contact_inbox.source_id,
                                          answers: { 'fullName' => 'Walisson' })

      expect(described_class.new(lead).perform).to be_nil
      expect(lead.reload.contact_id).to be_nil
    end

    it 'nao materializa um lead que ja foi concluido' do
      _contact, lead = visitor_session
      lead.update!(completed_at: Time.current)

      expect(described_class.new(lead).perform).to be_nil
    end

    it 'e idempotente: rodar duas vezes nao cria um segundo contato' do
      _contact, lead = visitor_session
      described_class.new(lead).perform

      expect { described_class.new(lead.reload).perform }.not_to change(Contact, :count)
    end

    it 'nao etiqueta quando a etiqueta esta vazia na conta' do
      enable_capture!('partial_lead_label' => '')
      _contact, lead = visitor_session

      materializado = described_class.new(lead).perform

      expect(materializado.label_list).to be_empty
      expect(materializado.custom_attributes['widget_lead_incomplete']).to be(true)
    end
  end

  describe Widget::PartialLeads::SweepJob do
    before { enable_capture! }

    it 'materializa o que passou da janela de abandono e deixa o recente em paz' do
      _velho_contact, velho = visitor_session          # parou ha 30 min
      recente_contact = create(:contact, account: account, email: nil)
      recente_inbox = create(:contact_inbox, contact: recente_contact, inbox: inbox)
      recente = create(:widget_partial_lead, account: account, inbox: inbox,
                                             session_id: recente_inbox.source_id,
                                             answers: { 'emailAddress' => 'novo@empresa.com' },
                                             last_answered_at: 1.minute.ago)

      described_class.perform_now(account.id)

      expect(velho.reload.contact_id).to be_present
      expect(recente.reload.contact_id).to be_nil
    end

    it 'APAGA o registro parcial vencido — dado pessoal de quem nao consentiu nao fica guardado' do
      enable_capture!('partial_lead_retention_days' => 7)
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 8.days.ago)
      recente = create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 1.day.ago)

      expect { described_class.perform_now(account.id) }.to change(WidgetPartialLead, :count).by(-1)
      expect(WidgetPartialLead.pluck(:id)).to eq([recente.id])
    end

    it 'expurga mesmo com a captura DESLIGADA — desligar a chave nao congela o que ja foi coletado' do
      account.update!(internal_attributes: account.internal_attributes.merge(
        'partial_lead_capture_enabled' => false, 'partial_lead_retention_days' => 7
      ))
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 8.days.ago)

      expect { described_class.perform_now(account.id) }.to change(WidgetPartialLead, :count).by(-1)
    end
  end

  describe Widget::PartialLeads::Report do
    it 'responde QUANTOS perdemos e ONDE' do
      create(:widget_partial_lead, account: account, inbox: inbox, step_reached: 3, step_key: 'phoneNumber')
      create(:widget_partial_lead, account: account, inbox: inbox, step_reached: 3, step_key: 'phoneNumber')
      create(:widget_partial_lead, account: account, inbox: inbox, step_reached: 1, step_key: 'fullName')
      create(:widget_partial_lead, account: account, inbox: inbox, step_reached: 4, completed_at: Time.current)

      relatorio = described_class.new(account: account).perform

      expect(relatorio[:started]).to eq(4)
      expect(relatorio[:completed]).to eq(1)
      expect(relatorio[:abandoned]).to eq(3)
      expect(relatorio[:completion_rate]).to be_within(0.0001).of(0.25)
      expect(relatorio[:by_step]).to eq({ 1 => 1, 3 => 2 })
      expect(relatorio[:by_step_name]).to eq({ 'phoneNumber' => 2, 'fullName' => 1 })
    end

    it 'devolve zeros sem dividir por zero quando ninguem comecou' do
      relatorio = described_class.new(account: account).perform

      expect(relatorio[:started]).to eq(0)
      expect(relatorio[:completion_rate]).to eq(0.0)
      expect(relatorio[:by_step]).to eq({})
    end

    it 'recorta por inbox e por janela de tempo' do
      outra = create(:channel_widget, account: account).inbox
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 1.hour.ago)
      create(:widget_partial_lead, account: account, inbox: outra, last_answered_at: 1.hour.ago)
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 40.days.ago)

      expect(described_class.new(account: account, inbox: inbox).perform[:started]).to eq(2)
      expect(described_class.new(account: account, since: 2.hours.ago).perform[:started]).to eq(2)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
