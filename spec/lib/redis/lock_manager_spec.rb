require 'rails_helper'

RSpec.describe Redis::LockManager do
  let(:lock_manager) { described_class.new }
  let(:lock_key) { 'test_lock' }

  after do
    # Cleanup: Ensure that the lock key is deleted after each test to avoid interference
    Redis::Alfred.delete(lock_key)
  end

  describe '#lock' do
    it 'acquires a lock and returns true' do
      expect(lock_manager.lock(lock_key)).to be true
      expect(lock_manager.locked?(lock_key)).to be true
    end

    it 'returns false if the lock is already acquired' do
      lock_manager.lock(lock_key)
      expect(lock_manager.lock(lock_key)).to be false
    end

    it 'can acquire a lock again after the timeout' do
      lock_manager.lock(lock_key, 1) # 1-second timeout
      sleep 2
      expect(lock_manager.lock(lock_key)).to be true
    end
  end

  describe '#unlock' do
    it 'releases a lock' do
      lock_manager.lock(lock_key)
      lock_manager.unlock(lock_key)
      expect(lock_manager.locked?(lock_key)).to be false
    end

    # O caso do GlitchTip tozi 111: o detentor passa do TTL (download de midia sem teto), a chave
    # expira, um segundo webhook adquire a "mesma" trava, e o primeiro, ao terminar, apagava a
    # trava DELE -- liberando um terceiro a rodar em paralelo.
    it 'does not release a lock that now belongs to someone else' do
      primeiro = described_class.new
      primeiro.lock(lock_key, 1)
      sleep 2

      segundo = described_class.new
      expect(segundo.lock(lock_key, 30)).to be true

      primeiro.unlock(lock_key)

      expect(segundo.locked?(lock_key)).to be true
    end

    it 'still releases when the caller did not acquire through this instance' do
      lock_manager.lock(lock_key)

      described_class.new.unlock(lock_key)

      expect(lock_manager.locked?(lock_key)).to be false
    end
  end

  describe '#locked?' do
    it 'returns true if a key is locked' do
      lock_manager.lock(lock_key)
      expect(lock_manager.locked?(lock_key)).to be true
    end

    it 'returns false if a key is not locked' do
      expect(lock_manager.locked?(lock_key)).to be false
    end
  end
end
