require 'rails_helper'

# O juiz recebia a transcrição e as tool calls, e NADA do contexto de origem — enquanto o
# agente avaliado recebe `meta_anuncio` e afins no próprio state. Resultado medido numa conta
# em 31/08/2026: a IA repetia o texto do criativo ("a partir de R$ 500/mês") e o juiz marcava
# `alucinacao` de severidade alta. Eram 61 dos 275 findings de alucinação em 30 dias.
RSpec.describe Captain::ConversationEvalService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:service) { described_class.new(account: account, conversation_display_id: conversation.display_id) }

  describe '#origem_context' do
    it 'is absent when the conversation carries no origin at all' do
      expect(service.send(:origem_context)).to be_nil
    end

    it 'carries the ad copy the agent also received' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => 'Saia do aluguel — a partir de R$ 500/mês' })

      texto = service.send(:origem_context)

      expect(texto).to include('Saia do aluguel — a partir de R$ 500/mês')
      expect(texto).to include('anúncio')
    end

    # A frase é o que impede o juiz de tratar a origem como palpite do avaliado.
    it 'tells the judge the origin is a legitimate source, not invention' do
      conversation.update!(custom_attributes: { 'meta_campanha' => 'Pacaembu' })

      expect(service.send(:origem_context)).to include('fonte legítima')
    end

    it 'includes every origin field that is filled' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => 'Anúncio X', 'meta_origem' => 'Instagram',
                                                'jornada' => 'Interesse em locação' })

      texto = service.send(:origem_context)

      expect(texto).to include('Anúncio X').and include('Instagram').and include('Interesse em locação')
    end

    # Atributo vazio não pode virar linha: "anúncio: " sem valor sugere que houve anúncio e
    # ninguém sabe qual, que é pior que não falar nada.
    it 'skips blank values instead of emitting an empty line' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => '  ', 'meta_origem' => 'Facebook' })

      texto = service.send(:origem_context)

      expect(texto).to include('Facebook')
      expect(texto).not_to include('anúncio')
    end

    it 'ignores attributes that are not about origin' do
      conversation.update!(custom_attributes: { 'codigos_buscados' => %w[123], 'rodizio_preferencia' => 'Gelson' })

      expect(service.send(:origem_context)).to be_nil
    end
  end

  # Mensagem de voz virava [audio] no transcript e o juiz não sabia o que tinha sido dito.
  # Conv 32808 (31/08/2026): o cliente perguntou por áudio onde ficavam as casas, a IA
  # respondeu "É aqui em Sinop mesmo" — resposta exata — e o juiz marcou
  # nao_respondeu_pergunta de severidade alta, porque para ele a IA falou de Sinop do nada.
  describe '#message_text' do
    it 'passa o texto normal adiante' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'quero alugar')

      expect(service.send(:message_text, m)).to eq('quero alugar')
    end

    it 'entrega o áudio TRANSCRITO, como o agente o recebeu' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation, content: nil)
      allow(m).to receive(:content_for_llm).and_return('[Voice Message] essas casinhas aonde mesmo?')

      expect(service.send(:message_text, m)).to include('essas casinhas aonde mesmo?')
    end
  end

  # Em 14k o juiz julgava contra uma FATIA da norma: 7 dos 8 agentes de uma conta ficavam
  # truncados, a Júlia perdendo 71%. A regra que ela cumpria morava no char 15.825 e virou
  # info_incorreta de severidade alta.
  describe 'limite da spec' do
    it 'cobre o maior prompt real com folga' do
      expect(described_class::SPEC_CHAR_LIMIT).to be >= 48_000
    end
  end

  # `transferencia_ausente` (IA -> outra IA) e `handoff_ausente` (IA -> humano) eram o mesmo
  # balde. Quem lê o relatório não distinguia "deixou o cliente sem gente" de "atendeu fora
  # da própria alçada", e a primeira é muito mais grave.
  describe 'categorias de falha' do
    # O enum é declarativo e o schema não expõe leitor público; ler o fonte é o jeito honesto
    # de afirmar que as duas categorias coexistem — o que importa é que uma não substituiu a
    # outra numa edição futura.
    let(:fonte) { Rails.root.join('enterprise/lib/captain/conversation_eval_schema.rb').read }

    it 'keeps handing off to a human as its own category' do
      expect(fonte).to include('handoff_ausente')
    end

    it 'adds routing to another AI as a separate category' do
      expect(fonte).to include('transferencia_ausente')
    end
  end

  # O transcript carregava só o TEXTO: uma resposta que a Meta recusou chegava ao juiz idêntica
  # a uma entregue. Conv 32979 (01/09/2026): as três mensagens de foto falharam, a cliente
  # escreveu "Não recebi fotos" e a IA reafirmou o envio — e o juiz não tinha como discordar.
  describe 'entrega que falhou' do
    it 'leaves a delivered message unmarked' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :outgoing, content: 'mandei as fotos')

      expect(service.send(:marca_de_falha, m)).to eq('')
    end

    it 'marks the message that never reached the client, with the reason' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :outgoing, content: 'mandei as fotos')
      m.update!(status: :failed, external_error: '100 - The parameter message[attachments][1][type] is required')

      marca = service.send(:marca_de_falha, m)

      expect(marca).to include('NÃO ENTREGUE')
      expect(marca).to include('attachments')
    end

    it 'still marks it when the channel gave no reason' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :outgoing, content: 'oi')
      m.update!(status: :failed)

      expect(service.send(:marca_de_falha, m)).to eq(' (NÃO ENTREGUE)')
    end
  end

  # Lead que fica esperando não é evento na transcrição, então nunca foi julgado. O juiz media
  # a conversa e ia embora — "terminou bem" e "parou no meio" chegavam iguais a ele.
  describe 'desfecho' do
    it 'is absent while the conversation is still warm' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'te mando as opções')

      expect(service.send(:desfecho_context)).to be_nil
    end

    it 'says who spoke last, how long ago, and whether anybody owns it' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :outgoing, content: 'qual bairro você prefere?')
      m.update_columns(created_at: 30.hours.ago)

      texto = service.send(:desfecho_context)

      expect(texto).to include('DESFECHO')
      expect(texto).to include('do atendimento, há 30h')
      expect(texto).to include('dono agora: ninguém')
    end

    # Cutucada programada é o que separa "abandonado" de "vai ser retomado".
    it 'reports the nudge so a scheduled follow-up is not read as abandonment' do
      m = create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :outgoing, content: 'ainda está aí?')
      m.update_columns(created_at: 30.hours.ago)
      conversation.update!(custom_attributes: { 'followup_count' => 2 })

      expect(service.send(:desfecho_context)).to include('sim, 2 já disparada(s)')
    end
  end

  # Categoria descrita no prompt mas ausente do enum do schema é recusada na chamada
  # estruturada — ela simplesmente nunca apareceria, sem erro nenhum.
  describe 'as categorias novas existem nos DOIS lugares' do
    let(:schema) { Rails.root.join('enterprise/lib/captain/conversation_eval_schema.rb').read }
    let(:prompt) { Rails.root.join('enterprise/lib/captain/prompts/conversation_eval.liquid').read }

    %w[nao_entregue pedido_ignorado afirmou_esgotamento lead_abandonado].each do |categoria|
      it "declares #{categoria} in the schema and describes it in the prompt" do
        expect(schema).to include(categoria)
        expect(prompt).to include("- #{categoria}:")
      end
    end
  end
end
