class Captain::ConversationEvalSchema < RubyLLM::Schema
  string :representatividade, enum: %w[atendimento_real interno outra_empresa bot_automatizado teste sem_atendimento],
                             description: 'Esta conversa é um atendimento real de cliente da imobiliária? ' \
                                          'atendimento_real = sim, cliente/lead real sendo atendido (EM ESCOPO). ' \
                                          'Os demais valores marcam FORA de escopo (ruído): interno=conversa/grupo interno da equipe; ' \
                                          'outra_empresa=a pessoa trata de assunto de OUTRA empresa, não da imobiliária; ' \
                                          'bot_automatizado=o interlocutor é um sistema automatizado (comando/erro em repetição), não uma pessoa; ' \
                                          'teste=conversa de teste da própria equipe; sem_atendimento=não houve interação real. Na dúvida, atendimento_real.'
  string :interesse, enum: %w[alto medio baixo nenhum],
                     description: 'Nível de interesse demonstrado pelo cliente ao longo do atendimento.'
  string :intencao, enum: %w[locacao venda duvida pos_venda reclamacao outro],
                    description: 'Intenção predominante do cliente.'
  string :funil, enum: %w[lead_novo qualificando qualificado handoff frio],
                 description: 'Estágio do funil em que a conversa terminou.'
  string :conduzido_por, enum: %w[ia humano misto],
                         description: 'Quem conduziu majoritariamente o atendimento.'
  string :handoff_timing, enum: %w[nao_precisou no_prazo tardio precisava_nao_fez],
                          description: 'Qualidade da passagem para o humano. nao_precisou=resolveu sem humano; ' \
                                       'no_prazo=passou na hora certa; tardio=passou tarde demais; ' \
                                       'precisava_nao_fez=exigia humano e ninguém passou.'
  integer :nota, minimum: 0, maximum: 10,
                 description: 'Nota geral do atendimento de 0 a 10 (qualidade, adequação, resolução).'
  string :resumo, description: 'Resumo objetivo do atendimento em 1 a 2 frases, em português.'
  array :objecoes, of: :string,
                   description: 'Objeções levantadas pelo cliente (ex.: preço, localização, garantia). Lista vazia se nenhuma.'
  array :respostas_problematicas,
        description: 'Uma entrada para CADA resposta [R#] do atendente que teve falha. Lista vazia se todas foram boas.' do
    object do
      integer :resposta_num, description: 'O número [R#] da resposta do atendente na transcrição.'
      string :quem, enum: %w[ia humano], description: 'Se a resposta foi da IA ou de um atendente humano.'
      string :categoria, enum: %w[
        alucinacao info_incorreta nao_respondeu_pergunta narrou_ferramenta
        tom_robotico repeticao exemplo_copiado quebrou_regra promessa_indevida
        handoff_ausente handoff_tardio fora_horario_mal_tratado
        contradisse_tool nao_chamou_tool_obrigatoria usou_tool_errada ignorou_erro_da_tool outro
      ], description: 'Categoria da falha.'
      string :severidade, enum: %w[baixa media alta], description: 'Gravidade da falha.'
      string :trecho, description: 'Trecho curto (verbatim) da resposta que evidencia a falha.'
      string :porque, description: 'Por que isso é uma falha, em 1 frase.'
    end
  end
end
