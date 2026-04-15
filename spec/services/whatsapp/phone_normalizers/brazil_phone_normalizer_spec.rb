require 'rails_helper'

describe Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer do
  let(:normalizer) { described_class.new }

  describe '#handles_country?' do
    it 'returns true for BR numbers' do
      expect(normalizer).to be_handles_country('5566996636632')
    end

    it 'returns false for non-BR numbers' do
      expect(normalizer).not_to be_handles_country('14155551212')
    end
  end

  describe '#normalize' do
    it 'adds the ninth digit when the number has 12 digits' do
      expect(normalizer.normalize('556696636632')).to eq('5566996636632')
    end

    it 'keeps 13-digit numbers unchanged' do
      expect(normalizer.normalize('5566996636632')).to eq('5566996636632')
    end
  end

  describe '#variants' do
    it 'returns both 12- and 13-digit forms when given a 13-digit number' do
      expect(normalizer.variants('5566996636632')).to contain_exactly('5566996636632', '556696636632')
    end

    it 'returns both forms when given a 12-digit number' do
      expect(normalizer.variants('556696636632')).to contain_exactly('556696636632', '5566996636632')
    end

    it 'skips the 12-digit variant when the mobile portion does not start with 9' do
      # landlines (8 digits, first digit != 9) should not produce a synthetic "without-nine" variant
      expect(normalizer.variants('556633174222')).to contain_exactly('556633174222', '5566933174222')
    end

    it 'returns the raw number when country does not match' do
      expect(normalizer.variants('14155551212')).to eq(['14155551212'])
    end
  end
end
