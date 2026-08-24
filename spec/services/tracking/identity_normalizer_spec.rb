require 'rails_helper'

# Bloco 5.11 — T-C5.2 e T-C5.3: normalizacao ANTES do hash.
#
# A ordem e o bloco inteiro. Hashear antes de normalizar produz um payload que o destino ACEITA com
# 200 e que nao casa com ninguem: o erro nao aparece em log, aparece no EMQ do cliente semanas
# depois. Por isso cada exemplo compara o digest produzido com o digest do valor NORMALIZADO — nao
# com "algum hash".
RSpec.describe Tracking::IdentityNormalizer do
  def sha256(value) = Digest::SHA256.hexdigest(value)

  describe 'e-mail' do
    it 'normaliza (apara e minuscula) e SO ENTAO hasheia' do
      expect(described_class.hashed_email('  Maria.Aparecida@Exemplo.COM ')).to eq(sha256('maria.aparecida@exemplo.com'))
    end

    it 'nao e o hash do valor cru — que e o erro que este arquivo existe para impedir' do
      cru = '  Maria.Aparecida@Exemplo.COM '

      expect(described_class.hashed_email(cru)).not_to eq(sha256(cru))
    end

    it 'recusa o que nao e e-mail em vez de hashear lixo' do
      expect(described_class.email('maria')).to be_nil
      expect(described_class.hashed_email('maria')).to be_nil
    end
  end

  describe 'telefone — as duas normalizacoes, porque os dois destinos pedem coisas diferentes' do
    it 'Meta: so digitos, com DDI' do
      expect(described_class.phone_digits('+55 (11) 98765-4321')).to eq('5511987654321')
      expect(described_class.hashed_phone_digits('+55 (11) 98765-4321')).to eq(sha256('5511987654321'))
    end

    it 'Google: E.164, com o "+"' do
      expect(described_class.phone_e164('+55 (11) 98765-4321')).to eq('+5511987654321')
      expect(described_class.hashed_phone_e164('+55 (11) 98765-4321')).to eq(sha256('+5511987654321'))
    end

    it 'e os dois produzem digests DIFERENTES — trocar um pelo outro zera o match em silencio' do
      expect(described_class.hashed_phone_digits('+5511987654321'))
        .not_to eq(described_class.hashed_phone_e164('+5511987654321'))
    end

    it 'telefone sem codigo de pais nao casa, entao nao vai' do
      expect(described_class.phone_digits('11987654321')).to be_nil
      expect(described_class.phone_e164('(11) 98765-4321')).to be_nil
    end
  end

  describe 'nome' do
    it 'minuscula e tira pontuacao, mantendo o acento (a doc da Meta aceita UTF-8)' do
      expect(described_class.person_name('  Maria-Aparecida! ')).to eq('mariaaparecida')
      expect(described_class.person_name('José')).to eq('josé')
    end
  end

  describe 'localidade' do
    it 'cidade sem espaco, sem acento e minuscula' do
      expect(described_class.city('São Paulo')).to eq('saopaulo')
    end

    it 'estado so aceita a sigla de duas letras' do
      expect(described_class.region('SP')).to eq('sp')
      expect(described_class.region('São Paulo')).to be_nil
    end

    it 'CEP so digitos, pais em ISO alpha-2 minusculo' do
      expect(described_class.postal_code('01310-100')).to eq('01310100')
      expect(described_class.country('BR')).to eq('br')
      expect(described_class.country('Brasil')).to be_nil
    end
  end

  describe 'o que NUNCA se hasheia (T-C5.3)' do
    it 'fbp, fbc, IP e user-agent nao tem metodo de hash aqui — hashear zera o match' do
      %i[hashed_fbp hashed_fbc hashed_client_ip_address hashed_client_user_agent].each do |metodo|
        expect(described_class).not_to respond_to(metodo)
      end

      expect(Tracking::PiiPolicy::ANONYMOUS_FIELDS).to include('fbp', 'fbc', 'client_ip_address', 'client_user_agent')
    end
  end

  describe 'valor ausente' do
    it 'nao vira digest de string vazia — campo ausente e ausente, nao um hash constante' do
      expect(described_class.digest('')).to be_nil
      expect(described_class.hashed_email(nil)).to be_nil
      expect(described_class.hashed_external_id(nil)).to be_nil
    end
  end
end
