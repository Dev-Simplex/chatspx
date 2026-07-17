require 'rails_helper'

describe Contacts::BrazilPhoneNormalizer do
  describe '.normalize' do
    context 'with landlines (DDD + 8 digits starting with 2-5)' do
      it 'keeps a landline starting with 3 unchanged' do
        # regression: +55 66 3531-1930 was turned into +55 66 9 3531-1930, a mobile that does not exist
        expect(described_class.normalize('+556635311930')).to eq('+556635311930')
      end

      it 'keeps landlines starting with 2, 4 and 5 unchanged' do
        expect(described_class.normalize('+551121119999')).to eq('+551121119999')
        expect(described_class.normalize('+554541119999')).to eq('+554541119999')
        expect(described_class.normalize('+556651119999')).to eq('+556651119999')
      end
    end

    context 'with legacy mobiles (DDD + 8 digits starting with 6-9)' do
      it 'adds the ninth digit to a mobile starting with 9' do
        expect(described_class.normalize('+556699857480')).to eq('+5566999857480')
      end

      it 'adds the ninth digit to mobiles starting with 6, 7 and 8' do
        expect(described_class.normalize('+556661119999')).to eq('+5566961119999')
        expect(described_class.normalize('+556671119999')).to eq('+5566971119999')
        expect(described_class.normalize('+556681119999')).to eq('+5566981119999')
      end
    end

    context 'with numbers that already have the ninth digit' do
      it 'keeps an 11-digit mobile unchanged' do
        expect(described_class.normalize('+5566998577480')).to eq('+5566998577480')
      end
    end

    context 'with numbers outside the normalizer scope' do
      it 'keeps non-brazilian numbers unchanged' do
        expect(described_class.normalize('+14155551212')).to eq('+14155551212')
      end

      it 'returns nil when the phone number is nil' do
        expect(described_class.normalize(nil)).to be_nil
      end

      it 'returns the value unchanged when the phone number is blank' do
        expect(described_class.normalize('')).to eq('')
      end

      it 'keeps numbers that are not in e164 format unchanged' do
        expect(described_class.normalize('+55 66 3531-1930')).to eq('+55 66 3531-1930')
      end
    end
  end
end
