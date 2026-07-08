# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactFlowSuppression, type: :model do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe 'associations' do
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { build(:contact_flow_suppression, contact: contact, account: account) }

    it { is_expected.to validate_inclusion_of(:category).in_array(described_class::CATEGORIES) }
    it { is_expected.to validate_inclusion_of(:reason).in_array(described_class::REASONS) }

    it 'enforces one suppression per (contact, category)' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing')
      dup = build(:contact_flow_suppression, contact: contact, account: account, category: 'marketing')
      expect(dup).not_to be_valid
    end

    it 'allows the same contact to be suppressed on a different category' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing')
      other = build(:contact_flow_suppression, contact: contact, account: account, category: 'utility')
      expect(other).to be_valid
    end
  end

  describe '.active' do
    it 'includes permanent (no expiry) and not-yet-expired rows, excludes expired' do
      permanent = create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing', expires_at: nil)
      future = create(:contact_flow_suppression, contact: contact, account: account, category: 'utility', expires_at: 1.hour.from_now)
      create(:contact_flow_suppression, contact: contact, account: account, category: 'all', expires_at: 1.hour.ago)

      expect(described_class.active).to contain_exactly(permanent, future)
    end
  end

  describe '.suppressed?' do
    it 'is true when an active suppression exists for the exact category' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing')
      expect(described_class.suppressed?(contact, 'marketing')).to be(true)
    end

    it 'is true for any category when an `all` suppression exists' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'all')
      expect(described_class.suppressed?(contact, 'marketing')).to be(true)
      expect(described_class.suppressed?(contact, 'utility')).to be(true)
    end

    it 'is false when the suppression is for a different category (marketing opt-out does not block utility)' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing')
      expect(described_class.suppressed?(contact, 'utility')).to be(false)
    end

    it 'ignores an expired suppression' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing', expires_at: 1.minute.ago)
      expect(described_class.suppressed?(contact, 'marketing')).to be(false)
    end

    it 'is false for a blank contact (fail-open)' do
      expect(described_class.suppressed?(nil, 'marketing')).to be(false)
    end
  end

  describe '.record_opt_out!' do
    it 'creates a permanent marketing opt-out suppression' do
      expect { described_class.record_opt_out!(contact: contact, account: account) }
        .to change(described_class, :count).by(1)
      row = described_class.last
      expect(row).to have_attributes(contact_id: contact.id, account_id: account.id,
                                     category: 'marketing', reason: 'opt_out', expires_at: nil)
    end

    it 'is idempotent — a repeat opt-out does not create a duplicate' do
      described_class.record_opt_out!(contact: contact, account: account)
      expect { described_class.record_opt_out!(contact: contact, account: account) }
        .not_to change(described_class, :count)
    end

    it 're-activates a previously expired suppression' do
      create(:contact_flow_suppression, contact: contact, account: account, category: 'marketing',
                                        reason: 'manual', expires_at: 1.day.ago)
      described_class.record_opt_out!(contact: contact, account: account)
      expect(described_class.suppressed?(contact, 'marketing')).to be(true)
    end
  end
end
