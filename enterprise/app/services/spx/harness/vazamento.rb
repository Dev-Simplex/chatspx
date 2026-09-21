# Trava anti-vazamento das fixtures do harness.
#
# Roda ANTES de qualquer byte tocar o disco dentro do repositório — não antes do commit.
# Arquivo real solto no worktree é commit acidental esperando acontecer, e o `spx-os` já
# provou que credencial versionada sobrevive a rescrita de repositório inteiro.
#
# É a SEGUNDA rede, de propósito: o Pseudonimizador é quem troca os valores, e esta classe
# existe justamente para o dia em que ele deixar um padrão passar. Pseudonimização manual (e
# automática) falha em silêncio; isto falha alto.
class Spx::Harness::Vazamento
  class Encontrado < StandardError; end

  # Telefone BR com 10 ou 11 dígitos, formatado ou não. O piso de 10 é o que separa telefone
  # de preço (`3.200`), de código de imóvel (`9908`) e de CEP (`78550-000`).
  TELEFONE = /(?:\+?55[\s.-]?)?(?:\(?\d{2}\)?[\s.-]?)?9?\d{4}[\s.-]?\d{4}\b/
  EMAIL = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
  # Logradouro seguido de número. Preço e código não casam: exigem a palavra do logradouro antes.
  ENDERECO = /\b(?:rua|av\.?|avenida|travessa|alameda|rodovia|estrada|pra[çc]a)\b[^,;\n]{2,60},?\s*
              (?:n[º°o]?\.?\s*)?\d{1,6}\b/ix
  CREDENCIAL = /\b(?:senha|password|passwd|pwd|api[_-]?key|token|secret|client[_-]secret)\b\s*[:=]\s*\S{4,}/i
  CHAVE_CONHECIDA = /\bsk-[A-Za-z0-9_-]{16,}|\b(?:ghp|gho|ghs)_[A-Za-z0-9]{20,}|\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\./

  PADROES = {
    'telefone' => TELEFONE,
    'e-mail' => EMAIL,
    'endereço com número' => ENDERECO,
    'credencial' => CREDENCIAL,
    'chave de API' => CHAVE_CONHECIDA
  }.freeze

  # O que a pseudonimização PRODUZ não pode ser confundido com o que ela deveria ter removido.
  # Sem esta lista, o telefone fictício `(66) 90000-0001` derrubaria a própria trava — e o
  # `senha: REDIGIDO` também, que foi o primeiro a cair quando o contrato entre as duas classes
  # virou teste.
  PSEUDONIMOS = /\bCONTATO-\d+\b|\(66\)\s?90000-\d{4}|contato-\d+@exemplo\.invalido|
                 Rua\ Fictícia,\ \d+|\bREDIGIDO\b/x

  class << self
    # Levanta se sobrou QUALQUER padrão sensível. Devolve o texto para encadear na gravação.
    def conferir!(texto, origem:)
      achados = varrer(texto)
      return texto if achados.empty?

      raise Encontrado, "vazamento em #{origem}: #{achados.join(', ')} — " \
                        'a fixture NÃO foi gravada. Corrija o Pseudonimizador, não esta trava.'
    end

    # Só reporta, sem levantar. Serve ao spec de varredura do diretório inteiro.
    def varrer(texto)
      limpo = texto.to_s.gsub(PSEUDONIMOS, '')
      PADROES.filter_map { |nome, rx| "#{nome} (#{limpo[rx]})" if limpo.match?(rx) }
    end
  end
end
