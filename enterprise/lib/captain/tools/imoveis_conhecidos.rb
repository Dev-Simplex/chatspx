# Trava anti-alucinação compartilhada: o que a busca DESTA conversa já devolveu, pelas duas
# chaves que a IA pode citar. Ler só `codigos_buscados` recusava imóvel legítimo — o
# track_codigos grava apenas o Codigo e corta em 40, enquanto o track_urls grava Codigo E
# ImoCodigo e corta em 60; quando a IA cita o ImoCodigo, ou quando a conversa é longa, o
# código real fica de fora e o cliente leva um "não" que ele não vê. Somar os dois mapas não
# afrouxa a trava: código que busca nenhuma retornou continua ausente dos dois.
#
# Vive num módulo porque duas ferramentas dependem da MESMA trava (mandar foto e montar a
# vitrine) — duas cópias divergiriam e uma delas passaria a aceitar código inventado.
module Captain::Tools::ImoveisConhecidos
  def codigos_conhecidos(conversation)
    attrs = conversation.custom_attributes || {}
    mapa = attrs['urls_imoveis']
    Array(attrs['codigos_buscados']).map(&:to_s) + (mapa.is_a?(Hash) ? mapa.keys.map(&:to_s) : [])
  end
end
