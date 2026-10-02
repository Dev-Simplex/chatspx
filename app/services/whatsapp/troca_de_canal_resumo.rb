# O que a conversa de destino recebe da origem quando o cliente é levado a outro canal
# (Whatsapp::ContactInviteService com `destino:`): quem atende lá, IA ou humano, não começa do zero.
#
#   nota     -> nota privada no topo da conversa de destino, para o time
#   atributo -> `custom_attributes['origem_canal']` da conversa de destino, que a IA de lá lê
#
# O resumo sai de um método só (`resumo`): o gerador de jornada da frente CHAT-180, quando existir
# no código, e o resumo que a IA da origem gravou (`resumo_atendimento_ia`) enquanto isso. O motivo
# da troca vem sempre à parte.
class Whatsapp::TrocaDeCanalResumo
  ATRIBUTO = 'origem_canal'.freeze
  GERADOR = 'Captain::Conversation::JourneySummary'.freeze

  def initialize(origem:, motivo:)
    @origem = origem
    @motivo = motivo
  end

  def nota
    [cabecalho, ("Resumo da origem:\n#{resumo}" if resumo), quem_atendeu].compact.join("\n\n")
  end

  def atributo
    [cabecalho, ("Resumo: #{resumo}" if resumo)].compact.join(' ')
  end

  private

  attr_reader :origem, :motivo

  def cabecalho
    canal = origem.inbox.nome_do_canal
    "Cliente veio da conversa ##{origem.display_id}, na caixa #{origem.inbox.name}#{" (#{canal})" if canal}. Motivo: #{motivo}"
  end

  def resumo
    return @resumo if defined?(@resumo)

    @resumo = gerado.presence || origem.custom_attributes['resumo_atendimento_ia'].to_s.strip.presence
  end

  # O gerador não levanta exceção por contrato; o rescue protege a troca de canal de um gerador que
  # ainda não cumpra isso.
  def gerado
    return @gerado if defined?(@gerado)

    @gerado = begin
      GERADOR.safe_constantize&.for(origem)
    rescue StandardError => e
      Rails.logger.warn("[TrocaDeCanalResumo] gerador falhou conv=#{origem.id}: #{e.class} #{e.message}")
      nil
    end
  end

  # O gerador de jornada já diz quem atendeu; sem ele, sai o dono atual da conversa de origem.
  def quem_atendeu
    return if gerado.present?

    dono = origem.assignee_agent_bot&.name&.then { |nome| "#{nome} (IA)" } || origem.assignee&.name
    "Quem atendia na origem: #{dono}" if dono.present?
  end
end
