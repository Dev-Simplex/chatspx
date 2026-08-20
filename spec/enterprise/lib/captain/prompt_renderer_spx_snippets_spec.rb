# frozen_string_literal: true

require 'rails_helper'

# ChatSPX (C-3 / C-14): estes testes travam duas correções do merge da v4.16.2 que nenhum teste do
# upstream cobre, porque as duas são sobre o CONTEÚDO do prompt que vai para o LLM em produção:
#
#  · C-3  — as 7 regras de conduta pt-BR que o merge reduziu a 3 bullets em inglês. Elas existem
#           porque a IA errou em produção sem elas.
#  · C-14 — `business_status` / `business_hours_text` deixaram de chegar ao prompt no caminho
#           DEFAULT: `runtime_context.liquid` só é renderizado quando `prompt_cache_system_enabled?`
#           está ligado, e ele é opt-in com default OFF. Os dois valores eram calculados por
#           `time_awareness` e descartados.
#
# Renderizam os templates REAIS (sem stub de File), justamente para pegar regressão de template.
RSpec.describe Captain::PromptRenderer do
  let(:availability_context) do
    { business_status: 'fechado agora, os atendentes voltam às 8h', business_hours_text: 'seg a sex, 8h às 18h' }
  end

  describe 'availability (C-14)' do
    %w[assistant scenario].each do |template|
      it "puts business_status and business_hours_text into the #{template} prompt" do
        out = described_class.render(template, availability_context)

        expect(out).to include('# Disponibilidade')
        expect(out).to include('O atendimento está fechado agora, os atendentes voltam às 8h.')
        expect(out).to include('# Horário de funcionamento')
        expect(out).to include('O horário de atendimento é: seg a sex, 8h às 18h.')
      end

      it "prints no availability block in the #{template} prompt when the keys are absent" do
        # É o caminho do prompt caching: split_instructions_for_cache passa
        # ctx.except(*VOLATILE_PROMPT_KEYS) ao template estável, então as duas chaves chegam
        # vazias aqui e o bloco volátil vem por runtime_context.liquid. Sem duplicação.
        out = described_class.render(template, {})

        expect(out).not_to include('# Disponibilidade')
        expect(out).not_to include('# Horário de funcionamento')
      end
    end
  end

  describe 'spx_conduct (C-3)' do
    %w[assistant scenario].each do |template|
      it "keeps the ChatSPX conduct rules in the #{template} prompt" do
        out = described_class.render(template, {})

        expect(out).to include('# Conduta no atendimento (ChatSPX)')
        # As 4 regras que o MERGE não cobria de forma nenhuma (nem por core_rules.liquid):
        expect(out).to include('não confirme nem negue que ela existe ou trabalha aqui')
        expect(out).to include('Nunca se passe por um atendente humano específico')
        expect(out).to include('Não peça nota de avaliação')
        expect(out).to include('Ping de presença na espera')
        # E as 2 que o MERGE cobria pela metade (perdeu o limite de 1 repergunta e o [IGNORAR]
        # de cobrança pura de espera):
        expect(out).to include('reperguntar no máximo uma vez')
        expect(out).to include('PURAMENTE cobrança ou desabafo da espera')
      end
    end
  end
end
