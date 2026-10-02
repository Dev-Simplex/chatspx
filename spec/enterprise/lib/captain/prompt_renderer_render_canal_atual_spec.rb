# frozen_string_literal: true

require 'rails_helper'

# O bloco "Onde você está atendendo" do molde compartilhado. O molde é de TODOS os clientes: sem
# papel configurado na caixa, o prompt tem que sair exatamente como antes do bloco existir.
RSpec.describe Captain::PromptRenderer, '.render' do
  let(:caminho) { Rails.root.join('enterprise/lib/captain/prompts/assistant.liquid') }
  let(:contexto) { { 'name' => 'Assistente', 'product_name' => 'Produto', 'channel_number' => '+5566999990000' } }
  let(:canal) { { 'tipo' => 'Instagram', 'caixa' => 'Perfil', 'papel' => 'Atendimento das redes' } }

  def renderizar(ctx)
    described_class.render('assistant', ctx)
  end

  it 'assistant.liquid sem canal atual, sai igual ao molde sem o bloco' do
    molde_sem_bloco = File.read(caminho).gsub(/\{% if (?:canal_atual|canais_destino) %\}.*?\{% endif -%\}\n/m, '')
    esperado = Liquid::Template.parse(molde_sem_bloco).render(
      contexto, registers: { file_system: Liquid::LocalFileSystem.new(Rails.root.join('enterprise/lib/captain/prompts/snippets'), '%s.liquid') }
    )

    expect(molde_sem_bloco).not_to include('canal_atual', 'canais_destino')
    expect(renderizar(contexto)).to eq(esperado)
  end

  it 'assistant.liquid com canal atual, diz o canal, a caixa e o papel' do
    texto = renderizar(contexto.merge('canal_atual' => canal))

    expect(texto).to include('# Onde você está atendendo')
    expect(texto).to include('no canal Instagram, na caixa "Perfil"')
    expect(texto).to include('O papel desta caixa na empresa: Atendimento das redes.')
  end

  it 'assistant.liquid com canais de destino, lista cada um com o papel' do
    destinos = [{ 'caixa' => 'Geral', 'tipo' => 'WhatsApp', 'papel' => 'Atendimento geral' }, { 'caixa' => 'Sem papel' }]
    texto = renderizar(contexto.merge('canais_destino' => destinos))

    expect(texto).to include("# Outros canais da empresa\n")
    expect(texto).to include(%(- "Geral" (WhatsApp): Atendimento geral\n- "Sem papel"\n))
  end
end
