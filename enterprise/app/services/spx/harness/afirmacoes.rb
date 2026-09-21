# Extrai as afirmações FACTUAIS de uma fala do agente, tipadas.
#
# A asserção de um cenário não é "o preço bateu". A mesma mensagem da conv 41803 afirma preço,
# número de quartos, suíte e vagas — quatro fatos, todos sobre um imóvel que nenhuma busca do
# atendimento devolveu. Assertar só o preço deixaria três invenções passarem no verde.
#
# Tipado e não "todo número da frase": `3 quartos` é afirmação sobre o imóvel, `R$ 2.400` é
# outra, e `17h30` não é nenhuma das duas. Número sem âncora não vira afirmação — o mesmo
# critério da Spx::Harness::Preservacao.
class Spx::Harness::Afirmacoes
  PADROES = {
    'preco' => /R\$\s*([\d.]+(?:,\d{2})?)|\b([\d.]+(?:,\d{2})?)\s*reais\b/i,
    'dormitorios' => /\b(\d{1,2})\s*(?:quartos?|dormit[óo]rios?)\b/i,
    'suites' => /\b(\d{1,2})\s*su[íi]tes?\b/i,
    'vagas' => /\b(\d{1,2})\s*vagas?\b/i,
    'area' => /\b([\d.]+)\s*m²/i,
    'codigo' => /\b(?:c[óo]d(?:igo)?\.?|im[óo]vel|ref\.?)\s*:?\s*(\d{3,6})\b/i
  }.freeze

  # Ferramentas que produzem evidência sobre imóvel. Registrar observação, resumo ou handoff
  # não comprova preço nenhum — é por isso que a lista é por NOME e não "qualquer tool".
  FONTES_DE_EVIDENCIA = %w[buscar_imovel buscar_empreendimento apresentar_imoveis
                           consultar_chave_imovel buscar_unidades].freeze

  class << self
    def extrair(texto)
      PADROES.flat_map do |tipo, rx|
        texto.to_s.scan(rx).filter_map do |casado|
          bruto = Array(casado).compact.first
          valor = normalizar(tipo, bruto)
          { 'tipo' => tipo, 'valor' => valor } if valor
        end
      end.uniq
    end

    # As buscas que aconteceram ANTES desta fala. Vazio significa que o agente afirmou sem ter
    # o que consultar — o caso da 41803, em que nenhuma das cinco chamadas é busca.
    def evidencia_antes(chamadas, instante)
      anteriores = Array(chamadas).select do |c|
        FONTES_DE_EVIDENCIA.include?(c['tool'].to_s) && c['em'].to_s < instante.to_s
      end
      anteriores.pluck('tool')
    end

    private

    def normalizar(tipo, bruto)
      return bruto.to_s if tipo == 'codigo'

      numero = bruto.to_s.delete('.').sub(',', '.').to_f
      numero.zero? ? nil : numero
    end
  end
end
