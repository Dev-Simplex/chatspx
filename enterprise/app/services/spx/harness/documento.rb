# Reconhece CPF e CNPJ pelo DÍGITO VERIFICADOR, não só pelo formato.
#
# É o que resolve o único conflito real do conjunto: CPF sem pontuação tem 11 dígitos, e
# celular brasileiro com DDD também. Separar por heurística ("o terceiro dígito é 9") erraria
# nos dois sentidos; o dígito verificador não erra — a chance de um telefone qualquer fechar a
# conta é de 1 em 100, e nenhum preço, CEP ou código de imóvel tem 11 ou 14 dígitos.
#
# Sequência de dígitos repetidos (00000000000, 11111111111) é rejeitada de propósito: é
# inválida por convenção E é a forma que o Pseudonimizador usa como substituto, então a trava
# não acusa a própria saída.
module Spx::Harness::Documento
  CPF_BRUTO = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/
  CNPJ_BRUTO = %r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b}
  # RG não tem dígito verificador padronizado — varia por estado. Só o formato pontuado e o
  # rótulo explícito são reconhecíveis; RG puro de 7 a 9 dígitos é indistinguível de número de
  # pedido ou código, e tentar pegá-lo derrubaria a trava em dado legítimo. Limite declarado.
  RG_FORMATADO = /\b\d{1,2}\.\d{3}\.\d{3}-?[\dXx]\b/
  RG_ROTULADO = /\bRG\b\s*:?\s*\d[\d.\-]{5,11}[\dXx]\b/i

  module_function

  def cpf?(texto)
    digitos = texto.gsub(/\D/, '')
    return false unless digitos.length == 11 && !repetidos?(digitos)

    verificador(digitos, 9, 10) && verificador(digitos, 10, 11)
  end

  def cnpj?(texto)
    digitos = texto.gsub(/\D/, '')
    return false unless digitos.length == 14 && !repetidos?(digitos)

    pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    pesos2 = [6] + pesos1
    verificador_com_pesos(digitos, pesos1, 12) && verificador_com_pesos(digitos, pesos2, 13)
  end

  # Qualquer ocorrência no texto que passe na validação. Devolve as strings encontradas.
  def encontrar(texto)
    achados = texto.to_s.scan(CPF_BRUTO).select { |v| cpf?(v) }
    achados + texto.to_s.scan(CNPJ_BRUTO).select { |v| cnpj?(v) }
  end

  def repetidos?(digitos)
    digitos.chars.uniq.size == 1
  end

  def verificador(digitos, ate, posicao)
    soma = (0...ate).sum { |i| digitos[i].to_i * (posicao - i) }
    resto = (soma * 10) % 11
    esperado = resto >= 10 ? 0 : resto
    digitos[ate].to_i == esperado
  end

  def verificador_com_pesos(digitos, pesos, posicao)
    soma = pesos.each_with_index.sum { |peso, i| digitos[i].to_i * peso }
    resto = soma % 11
    esperado = resto < 2 ? 0 : 11 - resto
    digitos[posicao].to_i == esperado
  end
end
