require 'rails_helper'

RSpec.describe Contacts::PhoneDuplicateCleanup do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:backup_dir) { Rails.root.join('tmp', "phone-dup-#{SecureRandom.hex(4)}").to_s }
  let!(:base) { create(:contact, account: account, name: 'Base', phone_number: '+5565988661415') }
  let!(:vazia) { duplicate_of(base, 'Vazia') }
  let!(:com_conversa) { duplicate_of(base, 'Com conversa') }

  before do
    create(:conversation, account: account, inbox: inbox, contact: base)
    create(:conversation, account: account, inbox: inbox, contact: base)
    create(:conversation, account: account, inbox: inbox, contact: com_conversa)
  end

  after { FileUtils.rm_rf(backup_dir) }

  # O indice unico impede criar a duplicata; aqui ela e montada como as que existem em producao.
  def duplicate_of(contact, name)
    ActiveRecord::Base.connection.remove_index(:contacts, name: Contact::PHONE_UNIQUE_INDEX, if_exists: true)
    create(:contact, account: account, name: name, phone_number: '+5565900000000').tap do |dup|
      dup.update_column(:phone_number, contact.phone_number) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'only describes when not applying' do
    groups = described_class.new(io: StringIO.new).perform

    expect(groups.size).to eq(1)
    expect(groups.first.base).to eq(base)
    expect(groups.first.to_delete).to eq([vazia])
    expect(groups.first.to_merge).to eq([com_conversa])
    expect(Contact.where(phone_number: base.phone_number).count).to eq(3)
  end

  it 'keeps the contact with more conversations, deletes the empty one and merges the other' do
    described_class.new(apply: true, backup_dir: backup_dir, io: StringIO.new).perform

    expect(Contact.where(account: account, phone_number: base.phone_number).pluck(:id)).to eq([base.id])
    expect(base.conversations.count).to eq(3)
    backup = JSON.parse(File.read(File.join(backup_dir, "#{account.id}-#{base.id}.json")))
    expect(backup['extras'].pluck('contact').pluck('id')).to contain_exactly(vazia.id, com_conversa.id)
  end
end
