# Resultado TIPADO de ferramenta.
#
# O problema que isto resolve: toda ferramenta devolve uma String, e nem o modelo nem o trace
# conseguem distinguir "a consulta rodou e o negócio não tem esse dado" de "a consulta caiu".
# As duas chegam como texto solto, e a segunda vira resposta de memória. Os três caminhos
# estão medidos em `06-auditoria-confiabilidade-2026-09-20.md`: o HttpTool colapsando toda
# falha numa string em inglês, a nota do turno seguinte filtrando `status: 'ok'`, e o
# `fetch_vista` devolvendo `[]` em não-200.
#
# O contrato com a gem `agents` NÃO muda: quem consome `perform` continua recebendo String.
# O tipo vive entre a ferramenta e o TraceRecorder, que desembrulha antes de devolver à gem e
# grava o status semântico em `captain_tool_calls` (ver Captain::Tools::TraceRecorder#perform).
# Ferramenta que ainda devolve String segue funcionando sem mudança — `envolver` cuida disso.
class Captain::Tools::Result
  # sucesso        — a consulta rodou e trouxe dado.
  # vazio_completo — a consulta rodou e o negócio NÃO tem o dado. Ausência CONFIRMADA: é o
  #                  único estado em que afirmar "não temos" é correto.
  # parcial        — parte foi confirmada, o resto não. Nunca autoriza "todos" nem "nenhum".
  # erro           — a consulta falhou. Ausência NÃO confirmada.
  # desconhecido   — a consulta respondeu, mas não dá pra afirmar presença nem ausência
  #                  (ex.: 2xx sem corpo). Separado de `erro` porque nada quebrou, e separado
  #                  de `vazio_completo` porque vazio aqui não é prova de ausência.
  STATUS = %i[sucesso vazio_completo parcial erro desconhecido].freeze

  # Vocabulário gravado na coluna `captain_tool_calls.status`. `sucesso` persiste como 'ok' e
  # `erro` como 'error' de propósito: é o vocabulário que já está no banco (default 'ok', scope
  # `with_error`) e o eval lê de lá. Trocar os dois invalidaria trace já gravado.
  STATUS_PERSISTIDO = {
    sucesso: 'ok',
    vazio_completo: 'vazio_completo',
    parcial: 'parcial',
    erro: 'error',
    desconhecido: 'desconhecido'
  }.freeze

  # Status em que a consulta CHEGOU a uma resposta do mundo — o dado pode ser usado.
  CONFIRMADOS = %w[ok vazio_completo parcial].freeze
  # Status em que a consulta NÃO chegou a uma resposta utilizável. Nunca vira "não temos".
  NAO_CONFIRMADOS = %w[error desconhecido].freeze

  attr_reader :status, :texto, :detalhe

  class << self
    def sucesso(texto, detalhe: nil)
      new(status: :sucesso, texto: texto, detalhe: detalhe)
    end

    def vazio_completo(texto, detalhe: nil)
      new(status: :vazio_completo, texto: texto, detalhe: detalhe)
    end

    def parcial(texto, detalhe: nil)
      new(status: :parcial, texto: texto, detalhe: detalhe)
    end

    def erro(texto, detalhe: nil)
      new(status: :erro, texto: texto, detalhe: detalhe)
    end

    def desconhecido(texto, detalhe: nil)
      new(status: :desconhecido, texto: texto, detalhe: detalhe)
    end

    # Ferramenta ainda não tipada devolve String. Sem isto, tipar uma tool exigiria tipar as
    # 29 de uma vez. O valor NÃO é convertido aqui — quem chama decide o que fazer com ele.
    def tipado?(valor)
      valor.is_a?(self)
    end
  end

  def initialize(status:, texto:, detalhe: nil)
    raise ArgumentError, "status de resultado inválido: #{status.inspect}" unless STATUS.include?(status)

    @status = status
    @texto = texto.to_s
    # Diagnóstico pra log/trace (classe da exceção, código HTTP). NUNCA vai pro modelo: é aqui
    # que mora o detalhe que não deve virar fala pro cliente.
    @detalhe = detalhe
    freeze
  end

  # A gem só sabe lidar com String; é por aqui que o resultado atravessa a fronteira.
  def to_s
    @texto
  end

  def status_persistido
    STATUS_PERSISTIDO.fetch(@status)
  end

  def erro?
    @status == :erro
  end

  # Só este estado autoriza o agente a afirmar que o dado não existe.
  def ausencia_confirmada?
    @status == :vazio_completo
  end
end
