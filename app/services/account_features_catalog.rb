# O catálogo de features de uma conta: o que existe, o que está ligado e o que a tela pode oferecer.
#
# Existe como serviço, e não dentro do controller, porque as marcações saem do próprio
# `config/features.yml` e precisam de um dono único. Sem isso a tela viraria uma segunda fonte de
# verdade que sai de sincronia — que é exatamente o problema de
# `app/javascript/dashboard/featureFlags.js`, mantido à mão e hoje já defasado (não tem
# `kanban_ux_v2`, `kanban_cursor_loading`, `crm_v2`).
class AccountFeaturesCatalog
  # As features que NÃO CABEM no bitmask. `accounts.feature_flags` é bigint (63 bits úteis) e a
  # POSIÇÃO no YAML define o bit; com 65 entradas, as posições 64 e 65 pedem 2^63 e 2^64. Ligar
  # qualquer uma levanta RangeError e derruba a requisição.
  #
  # CALCULADO, e não digitado: se alguém acrescentar feature no YAML a lista cresce sozinha, em vez
  # de virar mentira. Já documentado no fork em `app/services/kanban/realtime.rb`.
  SEM_BIT = Featurable::FEATURE_LIST.each_with_index.filter_map do |feature, indice|
    feature['name'] if (1 << indice) > ((2**63) - 1)
  end.freeze

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

  # Pedido de LIGAR uma que não cabe. Desligar é sempre permitido (inclusive para consertar uma conta
  # que ficou com bit inválido por outro caminho).
  def self.bloqueadas(pedidos)
    pedidos.select { |nome, valor| ligar?(valor) && SEM_BIT.include?(nome) }.keys
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
      # `available: false` = a tela TRAVA o interruptor, em vez de só avisar.
      available: SEM_BIT.exclude?(nome)
    }
  end
end
