# frozen_string_literal: true

require 'rails_helper'

# 4.18 — o registro parcial em si. O aceite de produto e medido nos specs de servico e de
# requisicao; aqui ficam as garantias do DADO: idempotencia por sessao, leitura tolerante
# do canal de contato e — a mais importante — as TRES rotas de exclusao.
RSpec.describe WidgetPartialLead do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  describe 'idempotencia por sessao' do
    it 'recusa duas linhas para a mesma (inbox, sessao) — a garantia e do BANCO' do
      create(:widget_partial_lead, account: account, inbox: inbox, session_id: 'abc')

      duplicada = build(:widget_partial_lead, account: account, inbox: inbox, session_id: 'abc')

      expect(duplicada).not_to be_valid
      expect { duplicada.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'aceita a mesma sessao em inboxes diferentes' do
      outra = create(:channel_widget, account: account).inbox
      create(:widget_partial_lead, account: account, inbox: inbox, session_id: 'abc')

      expect(build(:widget_partial_lead, account: account, inbox: outra, session_id: 'abc')).to be_valid
    end
  end

  describe 'canal de contato' do
    it 'le e-mail e telefone por nomes variados, tolerando caixa e separador' do
      lead = build(:widget_partial_lead, answers: { 'e_mail' => 'a@b.com', 'phone_number' => '+5511999998888' })

      expect(lead.email).to eq('a@b.com')
      expect(lead.phone_number).to eq('+5511999998888')
      expect(lead).to be_contactable
    end

    it 'nao e contactavel sem nenhum canal — cadastro sem forma de responder e lixo no painel' do
      lead = build(:widget_partial_lead, answers: { 'fullName' => 'Walisson', 'cargo' => 'Dev' })

      expect(lead.email).to be_nil
      expect(lead.phone_number).to be_nil
      expect(lead).not_to be_contactable
    end

    it 'ignora resposta em branco' do
      expect(build(:widget_partial_lead, answers: { 'emailAddress' => '   ' })).not_to be_contactable
    end
  end

  describe '.complete_for' do
    it 'marca concluida a resposta parcial da sessao, sem apagar a linha' do
      lead = create(:widget_partial_lead, account: account, inbox: inbox, session_id: 'abc')

      described_class.complete_for(inbox_id: inbox.id, session_id: 'abc')

      expect(lead.reload.completed_at).to be_present
      expect(described_class.count).to eq(1) # o relatorio precisa do denominador
    end

    it 'e silenciosa quando nao ha registro (captura desligada, visitante que nao respondeu nada)' do
      expect { described_class.complete_for(inbox_id: inbox.id, session_id: 'nao-existe') }
        .not_to raise_error
    end
  end

  # A cicatriz: uma FK sem cascade ja travou `conversation.destroy!` com InvalidForeignKey
  # nesta base. Cascade por multiplos caminhos ate a mesma linha filha e justamente o caso
  # em que a suite fica verde por schema.rb e a frota quebra por migration — por isso aqui
  # a exclusao e feita DE VERDADE, pelas tres pontas.
  describe 'exclusao dos pais (as tres rotas)' do
    it 'apagar o CONTATO apaga o registro parcial, e nao levanta' do
      contact = create(:contact, account: account)
      create(:widget_partial_lead, account: account, inbox: inbox, contact: contact)

      expect { contact.destroy! }.to change(described_class, :count).by(-1)
    end

    it 'apagar a INBOX apaga o registro parcial, e nao levanta' do
      create(:widget_partial_lead, account: account, inbox: inbox)

      expect { inbox.destroy! }.to change(described_class, :count).by(-1)
    end

    it 'apagar a CONTA apaga o registro parcial, e nao levanta' do
      create(:widget_partial_lead, account: account, inbox: inbox)

      expect { account.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
