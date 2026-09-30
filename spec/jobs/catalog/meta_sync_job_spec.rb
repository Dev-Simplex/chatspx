require 'rails_helper'

describe Catalog::MetaSyncJob do
  let(:account) { create(:account) }

  it 'reagenda a passada quando a Meta bate o limite, em vez de repetir em loop' do
    allow(Catalog::MetaSyncService).to receive(:new).with(account)
                                                    .and_return(instance_double(Catalog::MetaSyncService, perform: { limite_atingido: true }))

    expect { described_class.perform_now(account) }
      .to have_enqueued_job(described_class).with(account).at(a_value_within(1.minute).of(described_class::ESPERA_DO_LIMITE.from_now))
  end

  it 'não reagenda quando a passada termina normalmente' do
    allow(Catalog::MetaSyncService).to receive(:new).with(account)
                                                    .and_return(instance_double(Catalog::MetaSyncService, perform: { limite_atingido: false }))

    expect { described_class.perform_now(account) }.not_to have_enqueued_job(described_class)
  end
end
