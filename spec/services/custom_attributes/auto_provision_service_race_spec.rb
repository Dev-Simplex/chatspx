require 'rails_helper'

# Bloco 1.16 — a corrida do auto-provisionamento nao pode abortar a transacao de quem chamou.
#
# Este arquivo NAO usa fixtures transacionais, de proposito. Com elas so existe UMA conexao:
# a "outra requisicao" enxerga o que a nossa ainda nao commitou, a validacao de unicidade do
# Rails (custom_attribute_definition.rb:47-50) encontra a linha e o INSERT nunca sai. O indice
# unico jamais e tocado. Foi assim que a primeira versao deste teste passou no vacuo — media a
# validacao do Rails, nao a corrida.
#
# A corrida de verdade e outra: a outra requisicao ja INSERIU e ainda nao COMMITOU. Sob READ
# COMMITTED a linha e invisivel para o nosso SELECT (a validacao passa), mas o indice unico ja
# esta reservado — nosso INSERT bloqueia ate ela commitar e e o Postgres quem recusa. Ai o
# `rescue` em Ruby nao salva ninguem: a transacao inteira ja esta abortada.
describe CustomAttributes::AutoProvisionService do
  include CustomAttributeRaceHelpers

  self.use_transactional_tests = false

  # Um arquivo que tenha morrido no meio deixa linhas para tras, e a "outra requisicao" do
  # primeiro exemplo bateria na validacao do Rails em vez do indice.
  before(:all) { truncate_all_tables! } # rubocop:disable RSpec/BeforeAfterAll

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account, name: 'Antes da corrida') }

  after do
    finish_concurrent_requests!
    truncate_all_tables!
  end

  def definitions(model = 'contact_attribute')
    account.custom_attribute_definitions.where(attribute_model: model)
  end

  def service_for(attributes, model = :contact_attribute)
    described_class.new(account: account, attribute_model: model, custom_attributes: attributes)
  end

  def race_on(key, model: :contact_attribute)
    concurrent_definition_holding(account: account, key: key, model: model)
  end

  describe 'corrida real contra o indice unico' do
    it 'nao aborta a transacao de quem chamou' do
      race_on('carrinho_valor')
      attempts = nil

      ActiveRecord::Base.transaction do
        contact.update!(custom_attributes: { 'carrinho_valor' => 4200 })
        attempts = capture_definition_inserts { service_for('carrinho_valor' => 4200).perform }
        # Escrita DEPOIS da corrida, na MESMA transacao: numa transacao abortada esta linha
        # levanta PG::InFailedSqlTransaction. E o COMMIT la embaixo vira ROLLBACK calado.
        contact.update!(name: 'Depois da corrida')
      end

      expect(attempts.size).to eq(1)
      expect(attempts.first).to be_a(ActiveRecord::RecordNotUnique)
      expect(contact.reload.name).to eq('Depois da corrida')
      expect(contact.custom_attributes).to eq('carrinho_valor' => 4200)
      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
    end

    it 'segue provisionando as chaves seguintes do mesmo lote' do
      race_on('carrinho_valor')
      attempts = nil

      ActiveRecord::Base.transaction do
        attempts = capture_definition_inserts do
          service_for({ 'carrinho_valor' => 4200, 'cupom' => 'BLACK' }).perform
        end
      end

      expect(attempts.size).to eq(2)
      expect(attempts.map { |error| error&.class }).to eq([ActiveRecord::RecordNotUnique, nil])
      expect(definitions.pluck(:attribute_key)).to contain_exactly('carrinho_valor', 'cupom')
      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
    end

    it 'a conversa tambem sobrevive: o INSERT vem antes da escrita seguinte' do
      conversation_attributes = { 'origem_campanha' => 'black-friday' }
      race_on('origem_campanha', model: :conversation_attribute)
      inbox = create(:inbox, account: account)
      attempts = nil

      ActiveRecord::Base.transaction do
        attempts = capture_definition_inserts do
          service_for(conversation_attributes, :conversation_attribute).perform
        end
        create(:conversation, account: account, inbox: inbox, contact: contact, custom_attributes: conversation_attributes)
      end

      expect(attempts.size).to eq(1)
      expect(attempts.first).to be_a(ActiveRecord::RecordNotUnique)
      expect(account.conversations.count).to eq(1)
      expect(definitions('conversation_attribute').where(attribute_key: 'origem_campanha').count).to eq(1)
    end
  end

  describe 'a corrida pelo caminho de producao (ContactIdentifyAction)' do
    it 'commita o contato que a propria action acabou de gravar' do
      race_on('carrinho_valor')

      attempts = capture_definition_inserts do
        ContactIdentifyAction.new(
          contact: contact,
          params: { name: 'Ana do site', custom_attributes: { 'carrinho_valor' => 4200 } }
        ).perform
      end

      expect(attempts.size).to eq(1)
      expect(attempts.first).to be_a(ActiveRecord::RecordNotUnique)
      expect(contact.reload.custom_attributes).to eq('carrinho_valor' => 4200)
      expect(contact.name).to eq('Ana do site')
      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
    end
  end
end
