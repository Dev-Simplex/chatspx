# frozen_string_literal: true

# Tela `Configurações › Unidades`, aba Exceções — o que muda toda semana.
#
# Sem aprovação (§9.3, decidido em 25/08): quem é admin publica direto.
#
# Não existe `update`. Exceção é um fato datado, e corrigir uma é apagá-la e criar outra — o
# mesmo gesto que já se faz quando a campanha muda de data. `update` traria a pergunta "quem
# alterou o quê" sem que ninguém tenha pedido histórico.
class Api::V1::Accounts::UnidadeExcecoesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :excecao, only: [:destroy]

  # Só as que ainda não venceram. Exceção vencida morre sozinha — é o ponto do desenho, e
  # listá-la devolveria ao operador exatamente a limpeza manual que o n8n exigia.
  def index
    @excecoes = escopo.a_partir_de(Date.current).includes(:unidade).order(:data_inicio, :id)
  end

  def create
    @excecao = escopo.new(atributos)
    @excecao.save!
    render :show, status: :created
  end

  def destroy
    @excecao.destroy!
    head :ok
  end

  private

  def atributos
    excecao_params.to_h.merge(
      'account_id' => Current.account.id,
      'unidade_id' => unidade_alvo&.id
    )
  end

  # O alvo é resolvido DENTRO da conta: `find` numa relação já escopada devolve 404 para id de
  # outra conta, em vez de gravar uma exceção que atravessa a fronteira. O bug irmão disso está
  # anotado no PR #39 — `copilot/assign_conversation_service` seta `team_id` sem validar conta.
  def unidade_alvo
    id = excecao_params[:unidade_id]
    return nil if id.blank?

    Spx::Unidade.where(account_id: Current.account.id).find(id)
  end

  def excecao
    @excecao ||= escopo.find(params[:id])
  end

  def escopo
    Spx::UnidadeExcecao.where(account_id: Current.account.id)
  end

  def excecao_params
    params.require(:unidade_excecao).permit(
      :unidade_id, :etiqueta, :data_inicio, :data_fim, :fechada, :abre, :fecha, :motivo
    )
  end
end
