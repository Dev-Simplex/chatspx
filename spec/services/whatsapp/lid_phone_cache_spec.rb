require 'rails_helper'

RSpec.describe Whatsapp::LidPhoneCache do
  let(:session) { 'Simplex' }
  let(:lid) { '229480102662169' }

  after { Redis::Alfred.delete(described_class.key(session, lid)) }

  describe '.key' do
    it 'usa o formato combinado com o sync de grupos' do
      expect(described_class.key(session, lid)).to eq("waha:lid_pn:#{session}:#{lid}")
    end

    it 'aceita o JID cru e normaliza para digitos' do
      expect(described_class.key(session, "#{lid}@lid")).to eq(described_class.key(session, lid))
    end
  end

  describe '.write / .phone' do
    it 'faz round-trip do telefone' do
      described_class.write(session, lid, '5566999991234')

      expect(described_class.phone(session, lid)).to eq('5566999991234')
    end

    it 'normaliza o telefone gravado com JID' do
      described_class.write(session, lid, '5566999991234@c.us')

      expect(described_class.phone(session, lid)).to eq('5566999991234')
    end

    it 'normaliza o telefone gravado com +' do
      described_class.write(session, lid, '+5566999991234')

      expect(described_class.phone(session, lid)).to eq('5566999991234')
    end

    it 'devolve nil quando nunca foi gravado' do
      expect(described_class.phone(session, '999999999999999')).to be_nil
    end

    it 'ignora sessao em branco' do
      expect(described_class.write(nil, lid, '5566999991234')).to be(false)
    end
  end

  describe '.write_unresolved' do
    it 'grava o negativo e nao devolve telefone' do
      described_class.write_unresolved(session, lid)

      expect(described_class.phone(session, lid)).to be_nil
      expect(described_class).to be_unresolved(session, lid)
    end

    it 'grava negativo quando o telefone vem em branco' do
      described_class.write(session, lid, nil)

      expect(described_class).to be_unresolved(session, lid)
    end

    it 'distingue negativo de miss' do
      expect(described_class.read(session, lid)).to be_nil

      described_class.write_unresolved(session, lid)

      expect(described_class.read(session, lid)).to eq('')
    end
  end

  describe '.write_many' do
    let(:other_lid) { '260330953380002' }

    after { Redis::Alfred.delete(described_class.key(session, other_lid)) }

    it 'popula varias entradas de uma vez, aceitando JID cru dos dois lados' do
      written = described_class.write_many(session, "#{lid}@lid" => '5566999991234@c.us', other_lid => '5566988887777')

      expect(written).to eq(2)
      expect(described_class.phone(session, lid)).to eq('5566999991234')
      expect(described_class.phone(session, other_lid)).to eq('5566988887777')
    end

    it 'descarta pares sem telefone' do
      expect(described_class.write_many(session, lid => nil)).to eq(0)
    end
  end

  # TAREFA F3/2 — o cache escreve por DOIS caminhos diferentes:
  #   write/read   -> Redis::Alfred (namespaced por Redis::Namespace)
  #   write_many   -> pool CRU ($alfred.with { |c| c.pipelined { ... } })
  # Os dois so caem na mesma chave porque `redis-namespace` (1.10.0,
  # lib/redis/namespace.rb:311) tambem namespaceia o bloco `pipelined`. Um upgrade
  # major que mude isso manda o lote para outro namespace: o cache vira 100% miss,
  # sem erro, sem sintoma — so lentidao. Estes specs olham a chave FISICA (por baixo
  # do namespace) e quebram no momento em que os dois caminhos divergirem.
  describe 'chave fisica (blindagem contra upgrade do redis-namespace)' do
    let(:batch_lid) { '111111111111111' }
    let(:single_lid) { '222222222222222' }

    after do
      Redis::Alfred.delete(described_class.key(session, batch_lid))
      Redis::Alfred.delete(described_class.key(session, single_lid))
    end

    # Chaves como estao gravadas no Redis de verdade, sem o namespace ser removido.
    def physical_keys(pattern)
      $alfred.with { |conn| conn.redis.keys(pattern) } # rubocop:disable Style/GlobalVars
    end

    it 'write_many grava sob o MESMO prefixo de namespace que write/read usam' do
      described_class.write(session, single_lid, '5566988887777')
      described_class.write_many(session, batch_lid => '5566999991234')

      single_key = physical_keys("*#{described_class.key(session, single_lid)}").first
      batch_key = physical_keys("*#{described_class.key(session, batch_lid)}").first

      expect(single_key).to be_present
      expect(batch_key).to be_present
      expect(batch_key.delete_suffix(described_class.key(session, batch_lid)))
        .to eq(single_key.delete_suffix(described_class.key(session, single_lid)))
    end

    it 'a chave fisica carrega o prefixo do namespace configurado (alfred:)' do
      described_class.write_many(session, batch_lid => '5566999991234')

      expect(physical_keys("*#{described_class::KEY_PREFIX}*"))
        .to include("alfred:#{described_class.key(session, batch_lid)}")
    end

    it 'round-trip: o que write_many grava, read le' do
      described_class.write_many(session, batch_lid => '5566999991234')

      expect(described_class.read(session, batch_lid)).to eq('5566999991234')
    end
  end

  # GlitchTip issue 27: o cache negativo de 10 min nao freia um job de cadencia
  # HORARIA (expira sempre entre duas execucoes). Este backoff e o freio que faltava.
  describe 'memoria de falha (backoff)' do
    after { described_class.clear_failures(session, lid) }

    it 'nao esta em backoff antes da primeira falha' do
      expect(described_class).not_to be_cooling_down(session, lid)
      expect(described_class.failure_count(session, lid)).to eq(0)
    end

    it 'a primeira falha ja pula um ciclo inteiro do sweep' do
      expect(described_class.record_failure(session, lid)).to eq(1)

      expect(described_class).to be_cooling_down(session, lid)
      expect(described_class.backoff_for(1)).to eq(1.hour.to_i)
    end

    it 'conta os ciclos e alonga a espera a cada um' do
      3.times { described_class.record_failure(session, lid) }

      expect(described_class.failure_count(session, lid)).to eq(3)
      expect(described_class.backoff_for(3)).to be > described_class.backoff_for(1)
    end

    it 'satura no ultimo degrau em vez de crescer para sempre' do
      expect(described_class.backoff_for(99)).to eq(described_class::RETRY_BACKOFF.last.to_i)
      expect(described_class.backoff_for(0)).to eq(described_class::RETRY_BACKOFF.first.to_i)
    end

    it 'clear_failures devolve o LID para a fila normal' do
      2.times { described_class.record_failure(session, lid) }
      described_class.clear_failures(session, lid)

      expect(described_class).not_to be_cooling_down(session, lid)
      expect(described_class.failure_count(session, lid)).to eq(0)
    end

    it 'ignora sessao/lid em branco' do
      expect(described_class.record_failure(nil, lid)).to eq(0)
      expect(described_class.record_failure(session, nil)).to eq(0)
      expect(described_class).not_to be_cooling_down(nil, lid)
    end

    it 'nao usa a mesma chave do mapa LID->PN' do
      expect(described_class.failure_key(session, lid)).not_to eq(described_class.key(session, lid))
      expect(described_class.cooldown_key(session, lid)).not_to eq(described_class.key(session, lid))
    end

    it 'fail-open quando o Redis esta fora: nao segura o LID indevidamente' do
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError, 'down')

      expect(described_class).not_to be_cooling_down(session, lid)
    end

    it 'nao levanta ao registrar falha com o Redis fora' do
      allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError, 'down')

      expect(described_class.record_failure(session, lid)).to eq(0)
    end
  end

  describe 'resiliencia' do
    it 'nao levanta quando o Redis esta fora' do
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError, 'down')

      expect { described_class.phone(session, lid) }.not_to raise_error
      expect(described_class.phone(session, lid)).to be_nil
    end

    it 'nao levanta na escrita quando o Redis esta fora' do
      allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError, 'down')

      expect(described_class.write(session, lid, '5566999991234')).to be(false)
    end
  end
end
