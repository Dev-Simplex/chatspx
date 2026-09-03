require 'rake'
require 'rails_helper'

# As rake tasks nao sao carregadas pelo rails_helper; sem isto o `Rake::Task[...]` levanta
# "Don't know how to build task" e o bloco 1.18 nunca chegou a ser exercitado.
Rails.application.load_tasks if Rake::Task.tasks.empty?

RSpec.describe Rake::Task do
  describe 'tracking:seed_origin_definitions (bloco 1.18)' do
    subject(:task) { described_class['tracking:seed_origin_definitions'] }

    before { task.reenable }

    def origin_count(account)
      account.custom_attribute_definitions.where(attribute_key: Tracking::OriginAttributes.all_keys).count
    end

    it 'provisiona todas as contas e a segunda passagem não cria nada' do
      conta_a = create(:account)
      conta_b = create(:account)

      expect { task.invoke }.to output(/2 conta\(s\) processada\(s\), 48 definição\(ões\) criada\(s\)\./).to_stdout
      expect(origin_count(conta_a)).to eq(24)
      expect(origin_count(conta_b)).to eq(24)

      task.reenable
      expect { task.invoke }.to output(/2 conta\(s\) processada\(s\), 0 definição\(ões\) criada\(s\)\./).to_stdout
      expect(origin_count(conta_a)).to eq(24)
      expect(origin_count(conta_b)).to eq(24)
    end

    it 'ACCOUNT_ID limita a uma conta só' do
      alvo = create(:account)
      fora = create(:account)

      with_modified_env ACCOUNT_ID: alvo.id.to_s do
        expect { task.invoke }.to output(/1 conta\(s\) processada\(s\), 24 definição\(ões\) criada\(s\)\./).to_stdout
      end

      expect(origin_count(alvo)).to eq(24)
      expect(origin_count(fora)).to eq(0)
    end
  end
end
