require 'rails_helper'

# O mecanismo de feature de CONTA não tinha spec próprio até 28/08/2026, apesar de governar o que
# cada cliente enxerga. Estes exemplos travam as três coisas que se descobriu doer na prática:
# o default vir do BANCO e não do YAML, o bitmask estar estourado, e `enable_features!` falhar calado.
RSpec.describe Featurable do
  let(:account) { create(:account) }

  describe 'ligar e desligar' do
    it 'liga e desliga sem tocar nas outras' do
      account.enable_features!('campaigns', 'reports')
      account.disable_features!('reports')

      expect(account.reload.feature_enabled?('campaigns')).to be(true)
      expect(account.feature_enabled?('reports')).to be(false)
    end

    # A diferença que já causou estrago neste fork: `selected_feature_flags=` (do FlagShihTzu) ZERA
    # todos os bits antes de ligar os enviados. `enable_features` é incremental. Um endpoint que use
    # o primeiro apaga o que o cliente tinha ao receber uma requisição parcial.
    it 'enable_features e INCREMENTAL, nao substitui o conjunto' do
      account.enable_features!('campaigns')
      account.enable_features!('reports')

      expect(account.reload.enabled_features.keys).to include('campaigns', 'reports')
    end

    it 'selected_feature_flags= SUBSTITUI o conjunto inteiro (por isso nao serve para PATCH parcial)' do
      account.enable_features!('campaigns', 'reports')
      account.update!(selected_feature_flags: [:feature_campaigns])

      expect(account.reload.feature_enabled?('campaigns')).to be(true)
      expect(account.feature_enabled?('reports')).to be(false)
    end
  end

  # `accounts.feature_flags` é bigint (63 bits úteis) e a POSIÇÃO no config/features.yml define o bit.
  # Com 65 entradas, as duas últimas pedem 2^63 e 2^64 e NÃO CABEM. Este exemplo é o que impede
  # alguém de "só ligar todas" e derrubar a conta.
  describe 'o bitmask esta estourado' do
    let(:catalogo) { YAML.safe_load(Rails.root.join('config/features.yml').read) }

    it 'as features alem da posicao 63 nao cabem no bigint' do
      alem = catalogo.each_with_index.select { |_f, i| (1 << i) > (2**63 - 1) }.map { |f, _| f['name'] }

      expect(alem).to contain_exactly('conversation_required_attributes', 'advanced_assignment')
    end

    it 'ligar uma delas estoura, entao a tela precisa BLOQUEAR e nao so avisar' do
      expect { account.enable_features!('advanced_assignment') }.to raise_error(RangeError)
    end

    it 'a ultima que ainda cabe continua funcionando' do
      account.enable_features!('captain_tasks')

      expect(account.reload.feature_enabled?('captain_tasks')).to be(true)
    end
  end

  # A ordem do YAML é a identidade dos bits: inserir no meio remapeia todas as features seguintes e
  # corrompe TODAS as contas em silêncio. O arquivo avisa isso na primeira linha; aqui vira teste.
  describe 'a ordem do features.yml' do
    it 'nao pode mudar: a posicao de cada feature E o bit dela' do
      nomes = YAML.safe_load(Rails.root.join('config/features.yml').read).pluck('name')

      expect(nomes.first).to eq('inbound_emails')
      expect(nomes[15]).to eq('automations')
      expect(nomes.last).to eq('advanced_assignment')
      expect(nomes.size).to eq(65)
    end
  end

  # O default de conta NOVA não sai do YAML: sai da linha ACCOUNT_LEVEL_FEATURE_DEFAULTS em
  # installation_configs, lida no before_create. Quem mudar só o YAML não muda instalação nenhuma.
  describe 'default de conta nova' do
    it 'vem do InstallationConfig, e nao do features.yml' do
      InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
                        .update!(value: [{ 'name' => 'campaigns', 'enabled' => true },
                                         { 'name' => 'reports', 'enabled' => false }])
      GlobalConfig.clear_cache

      nova = create(:account)

      expect(nova.feature_enabled?('campaigns')).to be(true)
      expect(nova.feature_enabled?('reports')).to be(false)
    end
  end

  describe 'as 34 do padrao da frota' do
    # A mesma regra da migration FeaturesPadraoDaFrota, para o spec falhar se alguém mudar uma sem a
    # outra.
    let(:padrao) do
      fora = %w[captain_integration ip_lookup email_continuity_on_api_channel search_with_gin
                assignment_v2 saml shopify_integration notion_integration linear_integration
                crm_integration custom_reply_email custom_reply_domain channel_voice
                help_center_embedding_search reply_mailer_migration crm_v2 advanced_search_indexing
                disable_branding whatsapp_embedded_signup]
      YAML.safe_load(Rails.root.join('config/features.yml').read).reject do |f|
        f['deprecated'] || f['premium'] || fora.include?(f['name']) ||
          (f['chatwoot_internal'] && !f['enabled'])
      end.pluck('name')
    end

    it 'sao 34' do
      expect(padrao.size).to eq(34)
    end

    it 'todas cabem no bigint, entao ligar o padrao inteiro nao estoura' do
      expect { account.enable_features!(*padrao) }.not_to raise_error
      expect(account.reload.enabled_features.keys).to include(*padrao)
    end

    it 'nao inclui o Captain v1 nem canal depreciado' do
      expect(padrao).not_to include('captain_integration', 'channel_twitter')
    end

    it 'inclui o que o produto entrega, mesmo marcado como interno do Chatwoot' do
      expect(padrao).to include('kanban_ux_v2', 'automations', 'campaigns', 'captain_integration_v2')
    end
  end
end
