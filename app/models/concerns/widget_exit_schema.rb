# Schema de `widget_exit` (bloco 4.08) — a quinta chave de topo da configuracao do widget,
# irma de `widget_triggers` (3.02), `widget_tracking` (5.01) e `widget_appearance` (3.18).
#
# POR QUE UMA CHAVE NOVA, e nao um campo nas quatro que ja existem: o destino da saida nao e
# aparencia (tema/posicao/lancador), nao e gatilho (quando o widget aparece) e nao e tracking
# (identificador de plataforma). Enfiar um numero de telefone em `widget_appearance` deixaria o
# nome do schema mentindo sobre o que ele guarda — e o nome do schema e a documentacao que o
# proximo bloco vai ler. Chave de TOPO pelo mesmo motivo das outras quatro (A1): o merge do
# `#update` da inbox e RASO, entao um `widget_config` unico faria um PATCH parcial apagar as irmas.
#
# O QUE ELA GUARDA: o numero para onde o botao "continuar no WhatsApp" leva o visitante. Ate aqui
# `whatsAppExitNumber` era lido pelo componente e **nao era escrito por ninguem** — nem no banco,
# nem nos dois montadores. O `v-if` do componente nunca passava e o botao nunca renderizava; o
# unico teste que o via fabricava `window.chatwootWebChannel` com uma chave que producao nao emitia.
#
# SO DIGITOS, e a validacao e aqui e nao so na tela: `wa.me` recusa qualquer outra coisa, e um
# numero com mascara gravado no banco viraria link quebrado no site do cliente. A tela normaliza
# antes de mandar (`whatsAppDigits`), e este schema e quem GARANTE — a tela e a conveniencia, o
# servidor e a lei, porque e o servidor que grava.
module WidgetExitSchema
  # E.164: no maximo 15 digitos, contando o codigo do pais. O piso de 8 e a menor forma
  # internacional plausivel; nao ha piso "brasileiro" aqui de proposito — a frota tem cliente fora
  # do pais, e um minimo de 12 recusaria quem nao fez nada errado.
  #
  # A string VAZIA passa, e e o que permite ao administrador APAGAR o numero: sem ela, uma vez
  # configurada, a saida so poderia ser trocada — nunca desligada pelo campo.
  WHATSAPP_NUMBER_PATTERN = '^([0-9]{8,15})?$'.freeze

  # Ausente e o mesmo que vazio: sem numero o componente nao renderiza (regra 2 dele). Sem
  # migration e sem backfill — nenhuma inbox existente muda de comportamento (A4).
  DEFAULTS = {
    'whatsapp_number' => ''
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'whatsapp_number' => { 'type' => 'string', 'pattern' => WHATSAPP_NUMBER_PATTERN }
    },
    # Como nas irmas: este hash e publicado no HTML de TODA pagina do site do cliente. Chave nao
    # declarada aqui nao e ignorada — e recusada com 422, antes de virar byte publico.
    'additionalProperties' => false
  }.freeze
end
