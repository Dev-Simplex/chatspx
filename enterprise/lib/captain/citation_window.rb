# Janela em memória das FONTES recuperadas para UMA resposta (bloco 6.03).
#
# Hoje a fonte já chega ao modelo, mas como prosa dentro do prompt [M19]:
# `search_knowledge_tool.rb` devolve "#{texto}\n(fonte: #{source})". Prosa não sobrevive
# ao reload, não é clicável e não distingue "a IA citou" de "a IA inventou uma citação".
#
# Aqui a fonte vira DADO: quem recupera empurra, quem cria a mensagem lê e persiste em
# `content_attributes`. Mesma disciplina de Captain::ToolTraceWindow — quem abre fecha
# num `ensure`, e fora de uma janela aberta `record` é no-op.
#
# REGRA QUE SUSTENTA O ACEITE: a citação nasce do RETRIEVAL, nunca do texto do modelo.
# Nada aqui lê a resposta procurando "fonte:" — é justamente onde a invenção moraria.
module Captain::CitationWindow
  # Três fontes é o que cabe embaixo de uma bolha sem virar rodapé de artigo.
  MAX_CITATIONS = 3
  EXCERPT_LIMIT = 180

  module_function

  def open!
    Current.captain_citations = []
  end

  def close!
    Current.captain_citations = nil
  end

  def open?
    Current.captain_citations.is_a?(Array)
  end

  def citations
    Array(Current.captain_citations)
  end

  # `source` é o `external_link` do documento. Só vira link quando é HTTP(S) de verdade:
  # `PDF:` e `TEXT:` são identificadores internos, e transformá-los em href entregaria
  # ao visitante um link quebrado com a marca do cliente em volta.
  def record(title:, source:, excerpt:)
    return unless open?
    return if Current.captain_citations.size >= MAX_CITATIONS

    citation = build(title, source, excerpt)
    return if citation.nil? || duplicate?(citation)

    Current.captain_citations << citation
  end

  # Sem nome não há citação: um rodapé que diz "Fonte:" e nada mais é ruído.
  def build(title, source, excerpt)
    citation = {
      'title' => title.presence || public_url(source),
      'url' => public_url(source),
      'excerpt' => excerpt.to_s.strip[0, EXCERPT_LIMIT]
    }
    citation['title'].blank? ? nil : citation
  end

  def duplicate?(citation)
    Current.captain_citations.any? { |c| c['title'] == citation['title'] && c['url'] == citation['url'] }
  end

  def public_url(source)
    url = source.to_s.strip
    url.match?(%r{\Ahttps?://}i) ? url : nil
  end
end
