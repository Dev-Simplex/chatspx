# frozen_string_literal: true

# A IA respondendo um comentário público.
#
# Passa pelo MESMO portão da resposta manual (`Spx::Social::ResponderComentario`) — não existe
# caminho paralelo. Durante o piloto isso significa que a IA só alcança quem está na allowlist.
#
# ⚠️ A CONDUTA NÃO MORA AQUI. Este serviço monta os FATOS (quem comentou, o que escreveu, em que
# publicação) e entrega ao assistente configurado; tom, tamanho e o que fazer com pergunta que
# ele não sabe responder são instrução do assistente, no banco da conta. É a regra de isolamento
# do AGENTS.md: conduta de cliente nunca em código compartilhado — foi assim que conduta de
# óticas da Fábrica vazou pra Tozi.
#
# Também não há assistente padrão: sem `assistant_id` configurado, a IA não responde. O mesmo
# princípio da allowlist vazia — ausência de configuração significa "não", nunca "adivinhe".
class Spx::Social::ResponderComentarioComIa
  CABECALHO = '[Comentário público no Instagram, respondendo em nome da conta]'

  pattr_initialize [:comentario!]

  def perform
    return :desligada unless ativa?
    return :sem_assistente if assistant.blank?

    recusa = politica.motivo_da_recusa(comentario, forma)
    return recusa if recusa

    texto = gerar
    return :sem_resposta if texto.blank?

    Spx::Social::ResponderComentario.new(comentario: comentario, texto: texto, forma: forma).perform
  end

  private

  def gerar
    resposta = Captain::Assistant::AgentRunnerService
               .new(assistant: assistant, source: 'social_comment')
               .generate_response(message_history: [{ role: 'user', content: contexto }])
    limpar(extrair(resposta))
  rescue StandardError => e
    Rails.logger.error("[social] IA falhou no comentário #{comentario.external_id}: #{e.class} #{e.message}")
    nil
  end

  # O runner devolve um Hash de chaves STRING (`{"response" => ..., "agent_name" => ...}`), e a
  # primeira versão disto buscava com símbolo — resultado sempre nil, ou seja, a IA gerava a
  # resposta certa e nada era enviado.
  #
  # Passou despercebido porque o primeiro caso testado ao vivo era um `[IGNORAR]`: os dois
  # caminhos davam nil e se mascararam. E o spec não pegou porque o dublê devolvia String,
  # nunca exercitando o ramo de Hash — o dublê mentia sobre a forma do retorno real.
  def extrair(resposta)
    return resposta if resposta.is_a?(String)
    return nil unless resposta.is_a?(Hash)

    resposta.with_indifferent_access[:response]
  end

  # Os FATOS, rotulados. Sem exemplo de fala e sem molde de resposta: exemplo no contexto vira
  # resposta copiada — é a REGRA #1, e já aconteceu (o exemplo de endereço no prompt da Bruna
  # virou avenida inventada em conversa real).
  def contexto
    ([CABECALHO] + fatos + ["Comentário: #{comentario.texto}"]).join("\n")
  end

  def fatos
    publicacao = comentario.publicacao
    [
      ("Autor do comentário: @#{comentario.autor_username}" if comentario.autor_username.present?),
      ("Tipo da publicação: #{publicacao.tipo}" if publicacao&.tipo.present?),
      ("Legenda da publicação: #{publicacao.legenda}" if publicacao&.legenda.present?),
      # O que está ESCRITO nas imagens. Rotulado como leitura, e não apresentado como fato da
      # casa: se a visão errar um número, quem lê precisa saber de onde ele veio. Mesma
      # disciplina do rótulo de transcrição de áudio, que existe desde o falso positivo de 25/07.
      ("Texto lido nas imagens da publicação: #{leitura(publicacao)}" if leitura(publicacao).present?)
    ].compact
  end

  def leitura(publicacao)
    return nil unless publicacao&.has_attribute?(:leitura_midia)

    publicacao.leitura_midia
  end

  # `[IGNORAR]` é como o agente diz "não é pra responder isso" em todo o resto do produto.
  # Aqui vale igual: silêncio deliberado não é falha, e não deve virar resposta vazia enviada.
  def limpar(texto)
    limpo = texto.to_s.strip
    return nil if limpo.blank? || limpo.include?('[IGNORAR]')

    limpo
  end

  def ativa?
    config['ativa'].present?
  end

  def assistant
    @assistant ||= comentario.account.captain_assistants.find_by(id: config['assistant_id'])
  end

  # Qual superfície a IA usa. Explícito, e não deduzido de qual chave está ligada: responder em
  # público e responder no direct são decisões diferentes, e a conta pode querer humano no
  # público e IA no privado.
  def forma
    config['forma'].presence || 'privada'
  end

  def politica
    @politica ||= Spx::Social::PoliticaDeResposta.new(account: comentario.account)
  end

  def config
    @config ||= ((comentario.account.settings || {})['social_reply'] || {})['ia'].presence || {}
  end
end
