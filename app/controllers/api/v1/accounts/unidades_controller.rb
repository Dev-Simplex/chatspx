# frozen_string_literal: true

# Tela `Configurações › Unidades`, aba Unidades — Fase 2 do contrato docs/contratos/unidades.md.
#
# LEITURA APENAS, de propósito (§9.1, decidido em 25/08): endereço e telefone mudam uma vez por
# ano e a carga por `spx:unidades:carregar` já é idempotente por slug. O que muda toda semana é
# exceção, e é ela que ganhou tela de escrita. CRUD de unidade é Fase 3.
#
# Esta aba existe porque uma tela só de exceções seria cega: para criar uma exceção é preciso
# escolher o alvo (unidade ou etiqueta), e não haveria de onde tirar a lista — nem como conferir
# se a carga entrou certa.
#
# Admin-only (§9.2). Sem permissão por unidade, sem escopo por gerente.
class Api::V1::Accounts::UnidadesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    # Inativa continua na lista, marcada. Unidade que fechou é `ativa: false`, nunca linha
    # apagada — e quem opera precisa vê-la para saber que ela existiu.
    @unidades = escopo.includes(:horarios).order(ativa: :desc, nome: :asc)
    # As etiquetas alimentam o alvo da exceção em lote. Saem daqui, e não de uma constante,
    # porque cada cliente inventa as suas na carga.
    @etiquetas = @unidades.flat_map(&:etiquetas_normalizadas).uniq.sort
  end

  private

  def escopo
    Spx::Unidade.where(account_id: Current.account.id)
  end
end
