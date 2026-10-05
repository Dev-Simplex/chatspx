# O catálogo de features de uma conta: o que existe, o que está ligado e o que a tela pode oferecer.
#
# Existe como serviço, e não dentro do controller, porque as marcações saem do próprio
# `config/features.yml` e precisam de um dono único. Sem isso a tela viraria uma segunda fonte de
# verdade que sai de sincronia — que é exatamente o problema de
# `app/javascript/dashboard/featureFlags.js`, mantido à mão e hoje já defasado (não tem
# `kanban_ux_v2`, `kanban_cursor_loading`, `crm_v2`).
class AccountFeaturesCatalog
  NOMES = Featurable::FEATURE_LIST.pluck('name').freeze

  def initialize(account)
    @account = account
  end

  def to_h
    ligadas = @account.enabled_features
    { features: Featurable::FEATURE_LIST.map { |feature| linha(feature, ligadas) } }
  end

  def self.desconhecidas(nomes)
    nomes - NOMES
  end

  def self.ligar?(valor)
    ActiveModel::Type::Boolean.new.cast(valor).present?
  end

  private

  def linha(feature, ligadas)
    nome = feature['name']
    {
      name: nome,
      display_name: feature['display_name'],
      enabled: ligadas.key?(nome),
      premium: feature['premium'].present?,
      deprecated: feature['deprecated'].present?,
      internal: feature['chatwoot_internal'].present?,
      available: true
    }
  end
end
