# Garante que a pseudonimização não COMEU o dado de negócio.
#
# A trava anti-vazamento pergunta "sobrou algo que não podia ficar?". Esta pergunta o oposto:
# "sumiu algo que precisava ficar?". São falhas independentes e uma não cobre a outra — a
# primeira gravação da conv 41803 passou limpa na trava e teria sido reprovada aqui por dois
# motivos ao mesmo tempo:
#
#   - o R$ 2.400 que o agente afirmou sem busca desapareceu, porque a fala da IA foi
#     parafraseada junto com a do cliente. Sem esse número a fixture não testa o caso dela;
#   - o código 9412 sumiu do argumento do atualizar_resumo, porque duas regras de URL em
#     sequência reescreveram uma a saída da outra.
#
# Código de imóvel e valor monetário são o que os cenários asseveram. Se um deles não sobreviver
# à gravação, a fixture é uma casca e falha ALTO, antes de virar arquivo.
class Spx::Harness::Preservacao
  class Perdido < StandardError; end

  # `cód 9908`, `(cod. 9908)`, `imóvel 9908`. Não pega número solto: sem a palavra-âncora,
  # qualquer quantidade viraria "código" e a checagem acusaria o que ela mesma não precisa.
  CODIGO = /\b(?:c[óo]d(?:igo)?\.?|im[óo]vel|ref\.?)\s*:?\s*(\d{3,6})\b/i
  # R$ 1.200 · R$ 3.200,00 · R$ 731,55 · 2.400 reais
  VALOR = /R\$\s*([\d.]+(?:,\d{2})?)|\b([\d.]+(?:,\d{2})?)\s*reais\b/i

  class << self
    # `termos` é o vocabulário de NEGÓCIO que também precisa sobreviver: bairro, condomínio,
    # empreendimento, nome de agente de IA. Entrou porque a troca de nome passou a agir em
    # PEDAÇOS, e sobrenome brasileiro é nome de bairro com frequência — "Oliveira", "Campos",
    # "Rocha", "Lima". Se um dia a lista de proteção do Pseudonimizador falhar, o bairro some
    # da fixture e o cenário deixa de descrever a conversa; aqui isso falha alto.
    def conferir!(fixture, original:, origem:, termos: [])
      faltando = faltantes(fixture, original, termos: termos)
      return fixture if faltando.empty?

      raise Perdido, "perda em #{origem}: #{faltando.join(', ')} — presente no original e ausente " \
                     'na fixture. A fixture NÃO foi gravada: ela não testaria o caso dela.'
    end

    def faltantes(fixture, original, termos: [])
      perdidos(codigos(original), codigos(fixture), 'código')
        .concat(perdidos(valores(original), valores(fixture), 'valor'))
        .concat(perdidos(presentes(termos, original), presentes(termos, fixture), 'termo'))
    end

    # Só cobra o que ESTAVA no original: a lista de termos vem da conta inteira e a maioria não
    # aparece nesta conversa. Cobrar termo ausente dos dois lados acusaria perda que não houve.
    def presentes(termos, texto)
      Array(termos).map(&:to_s).uniq.select { |termo| texto.to_s.match?(/(?<![[:alpha:]])#{Regexp.escape(termo)}/i) }
    end

    def codigos(texto)
      texto.to_s.scan(CODIGO).flatten.compact.uniq
    end

    # Normaliza para comparar `R$ 2.400` com `2400` e com `2.400,00`: o que importa é o número
    # ter sobrevivido, não o formato em que ele aparece.
    def valores(texto)
      texto.to_s.scan(VALOR).map do |casado|
        bruto = casado.compact.first.to_s
        bruto.delete('.').sub(',', '.').to_f
      end.reject(&:zero?).uniq
    end

    private

    def perdidos(no_original, na_fixture, rotulo)
      (no_original - na_fixture).map { |v| "#{rotulo} #{v}" }
    end
  end
end
