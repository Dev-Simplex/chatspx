require 'rails_helper'

RSpec.describe Whatsapp::GroupSenderPhoneResolver do
  let(:session) { 'Simplex' }
  let(:lid) { '229480102662169' }
  let(:other_lid) { '260330953380002' }
  let(:waha_service) { instance_double(Waha::ApiService) }
  let(:resolver) { described_class.new(session) }

  # O lock da listagem e o circuito vivem no Redis com TTL de minutos: sem limpar
  # dos dois lados, a ordem aleatoria do RSpec deixa a suite intermitente.
  def clear_redis_keys
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session, lid))
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session, other_lid))
    Redis::Alfred.delete("#{described_class::LIST_LOCK_KEY}:#{session}")
    Redis::Alfred.delete("#{described_class::CIRCUIT_KEY}:#{session}")
  end

  before do
    allow(Waha::ApiService).to receive(:new).and_return(waha_service)
    clear_redis_keys
  end

  after { clear_redis_keys }

  describe '#phone_for' do
    it 'devolve o telefone e alimenta o cache' do
      allow(waha_service).to receive(:get_lid_phone_number).with(session, "#{lid}@lid").and_return('pn' => '5566999991234@c.us')

      expect(resolver.phone_for(lid)).to eq('5566999991234')
      expect(Whatsapp::LidPhoneCache.phone(session, lid)).to eq('5566999991234')
    end

    it 'nao bate na WAHA quando o cache ja tem o telefone' do
      Whatsapp::LidPhoneCache.write(session, lid, '5566999991234')

      expect(waha_service).not_to receive(:get_lid_phone_number)
      expect(resolver.phone_for(lid)).to eq('5566999991234')
    end

    it 'nao bate na WAHA quando o cache ja sabe que o LID nao resolve' do
      Whatsapp::LidPhoneCache.write_unresolved(session, lid)

      expect(waha_service).not_to receive(:get_lid_phone_number)
      expect(resolver.phone_for(lid)).to be_nil
    end

    it 'aceita o campo number no lugar de pn' do
      allow(waha_service).to receive(:get_lid_phone_number).and_return('number' => '5566999991234')

      expect(resolver.phone_for(lid)).to eq('5566999991234')
    end

    it 'ignora sessao em branco' do
      expect(waha_service).not_to receive(:get_lid_phone_number)
      expect(described_class.new(nil).phone_for(lid)).to be_nil
    end
  end

  describe 'fallback pela lista de LIDs' do
    before do
      allow(waha_service).to receive(:get_lid_phone_number).and_return('pn' => nil)
      allow(waha_service).to receive(:get_lids_list).and_return(
        [{ 'lid' => "#{lid}@lid", 'pn' => '5566999991234@c.us' },
         { 'lid' => "#{other_lid}@lid", 'pn' => '5566988887760@c.us' }]
      )
    end

    it 'encontra o telefone na lista' do
      expect(resolver.phone_for(lid)).to eq('5566999991234')
    end

    it 'aproveita a chamada e popula o cache dos outros participantes' do
      resolver.phone_for(lid)

      expect(Whatsapp::LidPhoneCache.phone(session, other_lid)).to eq('5566988887760')
    end

    it 'nao repete a listagem enquanto o lock esta ativo' do
      resolver.phone_for(lid)
      Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session, other_lid))

      expect(described_class.new(session).phone_for(other_lid)).to be_nil
      expect(waha_service).to have_received(:get_lids_list).once
    end
  end

  describe 'quando a WAHA nao conhece o LID' do
    it 'grava o negativo para nao martelar a API' do
      allow(waha_service).to receive(:get_lid_phone_number).and_return('pn' => nil)
      allow(waha_service).to receive(:get_lids_list).and_return([])

      expect(resolver.phone_for(lid)).to be_nil
      expect(Whatsapp::LidPhoneCache).to be_unresolved(session, lid)
    end
  end

  describe 'quando a WAHA esta fora ou lenta' do
    before do
      allow(waha_service).to receive(:get_lid_phone_number).and_raise(Waha::ApiService::ConnectionError, 'WAHA API timeout')
    end

    it 'propaga o erro para o job aplicar backoff' do
      expect { resolver.phone_for(lid) }.to raise_error(Waha::ApiService::ConnectionError)
    end

    it 'nao grava negativo (indisponibilidade nao e conhecimento sobre o LID)' do
      expect { resolver.phone_for(lid) }.to raise_error(Waha::ApiService::ConnectionError)
      expect(Whatsapp::LidPhoneCache.read(session, lid)).to be_nil
    end

    # Sessao morta gasta os 8s inteiros de read timeout. Sem o circuito, cada
    # mensagem do grupo paga esse pedagio.
    it 'abre o circuito e as chamadas seguintes nem tocam a WAHA' do
      expect { resolver.phone_for(lid) }.to raise_error(Waha::ApiService::ConnectionError)

      expect(described_class.new(session).phone_for(other_lid)).to be_nil
      expect(waha_service).to have_received(:get_lid_phone_number).once
    end
  end

  describe 'quando a sessao nao existe na WAHA' do
    before do
      allow(waha_service).to receive(:get_lid_phone_number).and_raise(Waha::ApiService::NotFoundError, 'Session not found')
    end

    it 'devolve nil sem levantar' do
      expect(resolver.phone_for(lid)).to be_nil
    end

    it 'grava negativo para nao repetir a chamada a cada mensagem' do
      resolver.phone_for(lid)

      expect(Whatsapp::LidPhoneCache).to be_unresolved(session, lid)
    end
  end
end
