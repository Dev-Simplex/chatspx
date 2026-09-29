require 'rails_helper'

# Ligar o app "Captador" em Integrações prepara a label e as definições de atributo da conta.
RSpec.describe Crm::Captador::SetupService do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }

  it 'roda pelo Crm::SetupJob quando o hook é criado' do
    expect { captador_hook_for(account) }.to have_enqueued_job(Crm::SetupJob)
  end

  it 'cria a label e as definições de atributo, sem duplicar ao religar' do
    hook = captador_hook_for(account)

    2.times { Crm::SetupJob.perform_now(hook.id) }

    expect(account.labels.pluck(:title)).to eq(['captador'])
    expect(account.custom_attribute_definitions.pluck(:attribute_key, :attribute_model)).to contain_exactly(
      %w[cnpj contact_attribute], %w[captador_lead_id contact_attribute], %w[captador_lead_id conversation_attribute]
    )
  end

  it 'mantém a definição de cnpj que a conta já tinha' do
    create(:custom_attribute_definition, account: account, attribute_key: 'cnpj', attribute_model: 'contact_attribute',
                                         attribute_display_name: 'CNPJ da empresa')

    described_class.new(captador_hook_for(account)).setup

    expect(account.custom_attribute_definitions.find_by(attribute_key: 'cnpj').attribute_display_name).to eq('CNPJ da empresa')
  end
end
