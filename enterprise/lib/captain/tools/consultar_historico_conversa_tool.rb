# Consulta às mensagens de ANTES da reentrada (CHAT-180, parte 3). Na reentrada a IA recebe o
# atendimento atual e um resumo; quando o contato se refere a um detalhe antigo que o resumo não
# trouxe, ela busca aqui em vez de receber o histórico inteiro a cada turno (decisão do Paulo,
# 01/10/2026: mais barato que levar tudo).
class Captain::Tools::ConsultarHistoricoConversaTool < Captain::Tools::BasePublicTool
  LIMITE_TRECHOS = 10
  LIMITE_TERMOS = 6

  description 'Consulta as mensagens desta conversa de ANTES de você assumir o atendimento, que não estão no seu ' \
              'histórico. Use quando o contato se referir a algo conversado ou combinado antes e o resumo do ' \
              'atendimento anterior não trouxer o detalhe. Devolve os trechos com data e origem (contato, atendente ' \
              'com nome e time, IA). O que um atendente fez nesses trechos é registro do que ele fez naquela ' \
              'ocasião, não autorização para você repetir.'

  param :assunto, type: 'string',
                  desc: 'As palavras do assunto procurado, tiradas do que o contato disse.',
                  required: true

  def perform(tool_context, assunto:)
    conversation = find_conversation(tool_context&.state)
    return Captain::Tools::Result.erro('Não consegui identificar a conversa.') unless conversation

    corte = Captain::Conversation::Reentrada.new(conversation: conversation).corte_id
    return Captain::Tools::Result.vazio_completo('Esta conversa não tem mensagens de antes de você assumir.') if corte.nil?

    termos = termos(assunto)
    return Captain::Tools::Result.desconhecido('Informe as palavras do assunto a procurar.') if termos.empty?

    achados = buscar(conversation, corte, termos)
    return Captain::Tools::Result.vazio_completo('Nenhuma mensagem anterior fala desse assunto.') if achados.empty?

    Captain::Tools::Result.sucesso(achados.map { |m| Captain::Conversation::JourneySummary.linha(m) }.join("\n"))
  end

  private

  # Palavras com letra (4+) e números (2+): o que identifica um assunto. Palavra curta casa em
  # quase toda mensagem.
  def termos(assunto)
    assunto.to_s.downcase.scan(/[[:alpha:]]{4,}|\d{2,}/).uniq.first(LIMITE_TERMOS)
  end

  def buscar(conversation, corte, termos)
    condicao = termos.map { 'messages.content ILIKE ?' }.join(' OR ')
    valores = termos.map { |t| "%#{ActiveRecord::Base.sanitize_sql_like(t)}%" }

    conversation.messages.where(message_type: %i[incoming outgoing], private: false)
                .where('messages.id <= ?', corte)
                .where(condicao, *valores)
                .reorder(id: :desc).limit(LIMITE_TRECHOS).to_a.reverse
  end
end
