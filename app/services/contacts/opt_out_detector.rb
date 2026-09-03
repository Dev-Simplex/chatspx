# Decide se uma mensagem do cliente é um pedido para PARAR de receber marketing.
#
# Existe porque o critério anterior — match exato da mensagem inteira contra
# `parar|sair|stop|cancelar` — nunca capturou ninguém: medido na conta 6, ZERO mensagens
# casaram isso desde sempre. Ninguém escreve "PARAR" sozinho; escreve "Não tenho interesse".
#
# Trocar por substring seria pior, e o comentário que justificava o match exato está certo:
# "não vou PARAR de procurar" não é opt-out. A amostra real mostra o tamanho do risco —
# estas duas seriam suprimidas por engano, e são leads quentes:
#
#   "Nao tenho interesse em compra no momento. Gostaria de algumas opções de casa para locação"
#   "não tenho interesse no momento não. Inclusive eu to com um terreno pra colocar a venda"
#
# Comprimento também não serve de régua: "Obrigada, mas não tenho interesse." tem 34 caracteres
# e é opt-out legítimo.
#
# O critério é a DOMINÂNCIA: é opt-out quando, removidas a frase de recusa, as saudações e as
# cortesias, não sobra pedido nenhum. Medido em 7.145 mensagens da conta 6: 305 contêm frase de
# recusa, 233 são dominadas por ela (232 contatos) e as 72 restantes trazem um pedido junto e
# são mantidas.
#
# Erra para o lado de NÃO suprimir: falso negativo custa um disparo a mais, falso positivo cala
# um cliente ativo.
class Contacts::OptOutDetector
  # Palavras que sozinhas JÁ são o pedido formal. Mantidas com match exato da mensagem inteira,
  # como sempre foram — é o caminho que o rodapé de template instrui ("responda PARAR").
  PALAVRAS_EXATAS = %w[parar sair stop cancelar descadastrar].freeze

  # Frases inequívocas de recusa. SEM o modificador /x: nele o espaço literal é ignorado e
  # `não tenho interesse` viraria `nãotenhointeresse`, que não casa com nada.
  RECUSA = Regexp.union(
    /n[ãa]o\s+(tenho|tem)\s+interesse/i,
    /sem\s+interesse/i,
    /n[ãa]o\s+quero\s+(mais\s+)?receber/i,
    /n[ãa]o\s+quero\s+mais\s+(nada|mensagens?)/i,
    /(para|pare|parem)\s+de\s+(mandar|enviar|me\s+mandar)/i,
    /n[ãa]o\s+(envie|envi[ea]m|mande|mandem)\s+mais/i,
    /n[ãa]o\s+me\s+(mande|mandem|envie|enviem)\s+mais/i,
    /me\s+tir[ea]\s+(da|dessa|desta)\s+lista/i,
    /sair\s+d[ae]\s+lista/i,
    /descadastr/i,
    /n[ãa]o\s+perturbe/i
  ).freeze

  # Saudação, cortesia e enchimento. O que sobra depois de tirar isto é o que decide.
  RUIDO = Regexp.union(
    /\b(bom\s+dia|boa\s+tarde|boa\s+noite)\b/i,
    /\b(ol[áa]|oi|opa|eae?)\b/i,
    /\b(obrigad[oa]|agrade[çc]o|grat[oa]|valeu|vlw)\b/i,
    /\bdesculp\w*/i,
    /\b(no|nesse|neste)\s+momento\b/i,
    /\bpor\s+(enquanto|hora|agora)\b/i,
    /\bpor\s+inquanto\b/i,
    /\bpela\s+lembran[çc]a\b/i,
    /\b(ent[ãa]o|mas|por[ée]m|contudo|todavia)\b/i,
    /\b(ok|blz|beleza|abra[çc]os?|at[ée]\s+mais|falou|tchau)\b/i,
    /\bpor\s+favor\b/i,
    /\b(nao|n[ãa]o|sim|hoje|agora|j[áa]|ainda|muito|bem|tudo|voc[êe]s?|vcs?|eu|me|meu|minha|te|lhe)\b/i
  ).freeze

  # Quantas palavras de conteúdo podem sobrar e a mensagem ainda ser só uma recusa. Duas ou
  # mais indicam que o cliente pediu OUTRA coisa — e aí a mensagem não é opt-out.
  MAX_RESTO = 2

  class << self
    def opt_out?(texto)
      conteudo = texto.to_s.strip
      return false if conteudo.blank?

      palavra_exata?(conteudo) || recusa_dominante?(conteudo)
    end

    private

    # A mensagem INTEIRA é a palavra-gatilho, tolerando pontuação e caixa. Deliberadamente
    # exato: sem isso, "não vou parar de procurar" descadastraria quem está procurando.
    def palavra_exata?(conteudo)
      PALAVRAS_EXATAS.include?(conteudo.gsub(/[[:punct:]]/, '').strip.downcase)
    end

    def recusa_dominante?(conteudo)
      return false unless conteudo.match?(RECUSA)

      resto = conteudo.gsub(RECUSA, ' ').gsub(RUIDO, ' ').gsub(/[[:punct:]]|\d/, ' ').squeeze(' ').strip
      resto.split.count { |palavra| palavra.length > 2 } < MAX_RESTO
    end
  end
end
