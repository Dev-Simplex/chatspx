require 'rails_helper'
require 'brazilian_phone_normalizer'

describe BrazilianPhoneNormalizer do
  it 'normalizes 13-digit with DDI' do
    expect(described_class.call('5511999999999')).to eq('5511999999999')
  end

  it 'inserts 9 for 12-digit number with DDI' do
    expect(described_class.call('551133333333')).to eq('5511933333333')
  end

  it 'adds DDI when missing (11 digits)' do
    expect(described_class.call('11999999999')).to eq('5511999999999')
  end

  it 'adds DDI and 9 when missing (10 digits)' do
    expect(described_class.call('1133333333')).to eq('5511933333333')
  end

  it 'returns nil for empty input' do
    expect(described_class.call(nil)).to be_nil
    expect(described_class.call('')).to be_nil
    expect(described_class.call('   ')).to be_nil
  end

  it 'strips formatting characters' do
    expect(described_class.call('(11) 9 9999-9999')).to eq('5511999999999')
  end

  it 'returns nil when only non-digit chars supplied' do
    expect(described_class.call('---')).to be_nil
  end
end
