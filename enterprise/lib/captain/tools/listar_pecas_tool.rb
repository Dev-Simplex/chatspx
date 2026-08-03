# Lista o material de apoio do produto que o lead está tratando. A tool é genérica e
# multi-tenant: o inventário vive no banco (produto.apresentacao), nunca em código.
#
# O inventário descreve MATERIAL e PÚBLICO, nunca sequência — não existe "peça do passo 2".
# Quem decide se manda material, qual e quando é o agente, lendo a conversa.
class Captain::Tools::ListarPecasTool < Captain::Tools::BasePublicTool
  include Captain::Tools::ProdutoApresentacao

  description 'Mostra o material de apoio já produzido que está disponível para este cliente ' \
              '(áudios, imagens, vídeos), com a descrição do que cada peça explica e para quem ' \
              'ela serve. Consulte antes de decidir mandar material: o que não estiver nesta ' \
              'lista não existe. Você decide se manda alguma, qual e em que momento.'

  def perform(tool_context)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    produto = produto_do_lead(conversation)
    return 'Não há material de apoio cadastrado para este cliente.' if produto.nil? || produto.pecas.empty?

    montar_resposta(produto)
  end

  private

  def montar_resposta(produto)
    linhas = produto.pecas.map { |p| "- id: #{p['id']} | tipo: #{p['tipo']} | #{p['descricao']}" }
    [
      "Material disponível para #{produto.nome}:",
      *linhas,
      produto.publico_alvo.presence && "Sobre este público: #{produto.publico_alvo}",
      'Para mandar uma, chame enviar_peca com o id exato de uma das peças acima.'
    ].compact.join("\n")
  end
end
