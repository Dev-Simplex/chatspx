require 'rails_helper'

RSpec.describe Captain::ToolCall do
  # Duas features consomem o mesmo trace. Sem o OR, ligar o contexto de ferramentas numa
  # conta sem eval não gravaria nada e a nota nasceria sempre vazia — falha silenciosa.
  describe '.gravar_para?' do
    let(:account) { create(:account) }

    it 'é falso quando a conta não pediu eval nem contexto' do
      expect(described_class.gravar_para?(account)).to be false
    end

    it 'é verdadeiro quando a conta usa o eval' do
      account.update!(custom_attributes: account.custom_attributes.merge('eval_enabled' => true))

      expect(described_class.gravar_para?(account.reload)).to be true
    end

    it 'é verdadeiro quando a conta usa só o contexto de ferramentas' do
      account.update!(custom_attributes: account.custom_attributes.merge('captain_tool_context' => true))

      expect(described_class.gravar_para?(account.reload)).to be true
    end

    it 'é falso para conta nula' do
      expect(described_class.gravar_para?(nil)).to be false
    end
  end
end
