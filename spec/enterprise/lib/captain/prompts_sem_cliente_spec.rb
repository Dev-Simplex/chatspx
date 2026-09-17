require 'rails_helper'

# Os moldes de enterprise/lib/captain/prompts servem TODOS os clientes (AGENTS.md, "Isolamento
# multi-cliente"). Cidade ou vertical escrita aqui vaza para as outras contas — já vazou das óticas
# para a imobiliária (645b58ceb) e de Sinop/imobiliária para todo mundo (auditoria de 15/09, B-3).
# Conduta de cliente mora no banco da conta.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Captain shared prompts' do
  it 'do not name a client city or vertical' do
    Dir[Rails.root.join('enterprise/lib/captain/prompts/*.liquid')].each do |path|
      expect(File.read(path)).not_to match(/sinop|imóve|imove|imobili|condomínio|iptu|óculos|oculos/i), path
    end
  end
end
# rubocop:enable RSpec/DescribeClass
