# Custom tool que AGE, em oposição à que consulta.
#
# O HttpTool serve as duas, e a diferença não é estética: metade das custom tools armadas da
# frota é POST contra CRM real (registrar cliente, agendar visita, criar/cancelar proposta).
# Para elas a pergunta não é "consegui ler o dado?" e sim "a operação aconteceu?" — e as
# mensagens de consulta respondem a pergunta errada de dois jeitos que custam dinheiro:
#
#   - um `Net::ReadTimeout` vira "não consegui", o modelo repete, e nasce a proposta duplicada;
#   - um 204 — resposta NORMAL de cancelamento — vira `desconhecido` e o modelo cancela de novo.
#
# Nenhuma mensagem daqui carrega o `NAO_INVENTE` da consulta: ele manda "diga que não conseguiu
# consultar", que é exatamente o que NÃO se pode dizer quando não se sabe se a ação ocorreu.
module Captain::Tools::HttpAcao
  # O enum do Captain::CustomTool hoje só aceita GET e POST; os outros verbos entram porque a
  # classificação não pode depender de o enum continuar restrito.
  ACOES_HTTP = %w[POST PUT PATCH DELETE].freeze
  # 4xx que NÃO são recusa: o servidor pode ter processado antes de desistir de responder.
  HTTP_INDETERMINADO = [408, 429].freeze

  ACAO_NAO_REALIZADA = 'A requisição não chegou a ser enviada, então esta ação NÃO foi realizada. ' \
                       'Isso pode ser dito com segurança. Tente de novo ou avise que não deu.'.freeze
  ACAO_INDETERMINADA = 'A requisição foi enviada e a confirmação não voltou: NÃO se sabe se esta ' \
                       'ação foi realizada. NÃO repita a operação — repetir pode duplicá-la — e não ' \
                       'afirme nem que foi feita nem que falhou. Diga que precisa confirmar e acione ' \
                       'uma pessoa do time para verificar.'.freeze
  ACAO_RECUSADA = 'A ação foi recusada pelo sistema e NÃO foi concluída. Não repita sem mudar o ' \
                  'que foi enviado.'.freeze
  ACAO_FEITA_SEM_LEITURA = 'A ação foi realizada com sucesso. A confirmação detalhada não pôde ser ' \
                           'lida, então não descreva detalhes do resultado.'.freeze
  ACAO_CONFIRMADA = 'A ação foi realizada com sucesso (o sistema confirmou sem devolver conteúdo).'.freeze

  private

  # O que a tool FAZ, não o que ela devolve.
  def acao?
    ACOES_HTTP.include?(@custom_tool.http_method.to_s.upcase)
  end

  def resultado_acao(erro)
    detalhe = "#{erro.classe}: #{erro.message}"
    case desfecho_da_acao(erro)
    when :realizada then Captain::Tools::Result.sucesso(ACAO_FEITA_SEM_LEITURA, detalhe: detalhe)
    # `desconhecido`, não `erro`: no trace e na nota do turno seguinte isto precisa aparecer como
    # "não se sabe", que é diferente de "falhou".
    when :indeterminada then Captain::Tools::Result.desconhecido(ACAO_INDETERMINADA, detalhe: detalhe)
    when :recusada then Captain::Tools::Result.erro(ACAO_RECUSADA, detalhe: detalhe)
    else Captain::Tools::Result.erro(ACAO_NAO_REALIZADA, detalhe: detalhe)
    end
  end

  # A única prova de que a ação NÃO ocorreu é a requisição não ter saído. Tudo que foi enviado e
  # não voltou confirmado é indeterminado — inclusive 5xx, porque o servidor pode ter gravado
  # antes de falhar ao responder.
  def desfecho_da_acao(erro)
    return :nao_realizada unless erro.enviada?

    codigo = erro.status.to_i
    return :realizada if codigo.between?(200, 299)
    return :recusada if codigo.between?(400, 499) && HTTP_INDETERMINADO.exclude?(codigo)

    :indeterminada
  end
end
