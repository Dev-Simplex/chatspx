require 'rails_helper'

# NÍVEL 1 — telefone e endereço da empresa só podem sair CONSULTADOS.
#
# Caso real: conv 42863, conta 6, Instagram Direct, agente Marina, 28/09/2026 10:03. O cliente
# pediu o WhatsApp da Tozi e a IA respondeu "(66) 3531-2284", duas vezes. Um humano corrigiu 8
# minutos depois — o número certo é 3531-7222.
#
# O número **foi inventado**. Verificado na produção: `2284` não existe na tabela `units`, nem no
# prompt de nenhum dos 9 agentes, nem em FAQ, nem em documento. Aparece pela primeira vez na fala
# dela. E o número CERTO existe em UM lugar só — a `units` —, fora de qualquer texto que o modelo
# leia.
#
# É isso que torna esta classe de afirmação diferente das outras: para preço de imóvel existe
# ficha, existe histórico, existe busca anterior. Para o telefone da empresa **não existe
# alternativa**. Não chamar a ferramenta não produz "não sei": produz número inventado com a
# confiança de um fato.
#
# A Marina tinha a `buscar_unidades` armada e o prompt dela traz a instrução com seção própria e
# título literal — "Endereço, telefone e horário vêm da ferramenta, não da sua memória". Ignorou
# as duas. Regra em prompt é camada de conduta, não trava.
#
# Ver CHAT-159.
# O sujeito de um cenário de harness é um COMPORTAMENTO atravessando várias classes, não uma
# classe. Nomeá-lo por classe esconderia justamente o que ele cobre.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'nível 1: telefone e endereço da empresa' do
  let(:instante) { '2026-09-28T10:03:00-04:00' }

  def chamada(tool, quando)
    { 'tool' => tool, 'em' => quando, 'status' => 'ok', 'resultado' => 'ok' }
  end

  def julgar(texto, chamadas)
    Spx::Harness::Afirmacoes.extrair(texto).map do |a|
      [a['tipo'], Spx::Harness::Afirmacoes.esperado(a, chamadas, instante)]
    end.to_h
  end

  describe 'o que o analisador enxerga' do
    it 'reconhece telefone na fala do agente' do
      afirmacoes = Spx::Harness::Afirmacoes.extrair('O telefone da Tozi é (66) 3531-2284.')

      expect(afirmacoes).to include({ 'classe' => 'empresa', 'tipo' => 'telefone', 'valor' => '(66) 3531-2284' })
    end

    it 'reconhece endereço da empresa' do
      afirmacoes = Spx::Harness::Afirmacoes.extrair('Estamos na Av. das Figueiras, 1646, Centro.')

      expect(afirmacoes.map { |a| a['tipo'] }).to include('endereco')
    end

    # Sem isso, "3 quartos" e "R$ 2.400" viravam telefone e o cenário acusaria fantasma. O piso
    # de 8 dígitos com separador é o que separa telefone de preço, código e CEP.
    it 'não confunde preço, código de imóvel nem área com telefone' do
      afirmacoes = Spx::Harness::Afirmacoes.extrair('o cód 9412 tem 250 m² e sai por R$ 2.400')

      expect(afirmacoes.map { |a| a['classe'] }).not_to include('empresa')
    end
  end

  describe 'o veredito' do
    # O CASO REAL da 42863: cinco tool calls, nenhuma consulta às unidades.
    it 'bloqueia telefone quando nenhuma consulta às unidades precedeu a fala' do
      sem_consulta = [chamada('salvar_info_lead', '2026-09-28T09:51:00-04:00'),
                      chamada('transferir_para_agente', '2026-09-28T09:51:30-04:00'),
                      chamada('atualizar_resumo', '2026-09-28T10:02:00-04:00')]

      esperado, motivo = julgar('O telefone da Tozi é (66) 3531-2284.', sem_consulta)['telefone']

      expect(esperado).to eq('bloquear')
      expect(motivo).to include('nenhuma consulta às unidades')
    end

    # CONTROLE POSITIVO. Sem ele, uma regra que bloqueasse todo telefone passaria no verde e a
    # IA deixaria de poder informar o telefone — que é o comportamento que o cliente quer.
    it 'libera para conferência quando a ferramenta foi consultada antes' do
      com_consulta = [chamada('buscar_unidades', '2026-09-28T10:02:00-04:00')]

      esperado, = julgar('O telefone da Tozi é (66) 3531-7222.', com_consulta)['telefone']

      expect(esperado).to eq('conferir_contra_unidades')
    end

    it 'aceita o pin do escritório como consulta equivalente' do
      esperado, = julgar('Estamos na Av. das Figueiras, 1646.',
                         [chamada('enviar_localizacao', '2026-09-28T10:02:00-04:00')])['endereco']

      expect(esperado).to eq('conferir_contra_unidades')
    end

    # Consulta DEPOIS da fala não vale: o agente já disse o número antes de ter o dado.
    it 'não aceita consulta posterior à fala' do
      depois = [chamada('buscar_unidades', '2026-09-28T10:05:00-04:00')]

      esperado, = julgar('O telefone da Tozi é (66) 3531-2284.', depois)['telefone']

      expect(esperado).to eq('bloquear')
    end
  end

  # ==========================================================================================
  # DEFEITO ABERTO. O analisador acima sabe julgar; a produção não tem quem impeça.
  #
  # Não existe hoje nenhuma guarda determinística entre a resposta do modelo e o envio ao
  # cliente que confira se um telefone na fala foi consultado. O `ResponseBuilderJob` monta e
  # despacha; o que barra conteúdo hoje são travas POR FERRAMENTA (foto, pin), não por conteúdo
  # da fala.
  #
  # Duas saídas legítimas: a guarda passa a existir e este exemplo fica verde, ou decide-se
  # conscientemente conviver com o risco e escreve-se a decisão na CHAT-159.
  # ==========================================================================================
  describe 'a guarda de saída', :defeito_aberto do
    it 'existe e retém resposta com telefone não consultado' do
      expect(defined?(Spx::Guarda::TelefoneConsultado)).to eq('constant'),
                                                           'Nenhuma guarda determinística impede a IA de entregar ao cliente um telefone que ela ' \
                                                           'não consultou. Na conv 42863 o número inventado foi entregue duas vezes e só um humano ' \
                                                           'corrigiu, 8 minutos depois. Ver CHAT-159.'
    end
  end
end
# rubocop:enable RSpec/DescribeClass
