require 'rails_helper'

# NÍVEL 1 — segurança determinística.
#
# Modelo roteirizado (a sequência de chamadas está escrita aqui), ferramentas REAIS, HTTP
# mockado no limite da rede. A asserção é binária: o cliente recebeu a foto ou não recebeu.
#
# A conta é fictícia de ponta a ponta — host, chave, códigos e bairros. Nada aqui depende de
# acervo de cliente nenhum, e o cenário roda igual em qualquer máquina e na CI.
# O sujeito de um cenário de harness é um COMPORTAMENTO atravessando várias classes, não uma
# classe. Nomeá-lo por classe esconderia justamente o que ele cobre.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'nível 1: trava anti-alucinação do envio de fotos' do
  # `captain_tool_context` liga o trace (Captain::ToolCall.gravar_para?) e, com ele, a nota do
  # turno seguinte. Sem o flag a conta não grava linha nenhuma e o cenário ficaria cego
  # justamente sobre o que o modelo recebe depois.
  let(:account) do
    create(:account, custom_attributes: { 'vista_base_url' => 'https://acervo.ficticio.invalid',
                                          'vista_api_key' => 'chave-ficticia',
                                          'site_domain' => 'www.ficticia.invalid',
                                          'captain_tool_context' => true })
  end
  let(:assistant) { create(:captain_assistant, account: account, config: { 'fotos_carrossel' => true }) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:roteiro) { Spx::Harness::Nivel1::Roteiro.new(assistant: assistant, conversation: conversation) }

  # Dois imóveis fictícios: o 4001 existe na busca, o 4002 existe no acervo mas NUNCA aparece
  # numa busca desta conversa. É essa diferença que a trava deveria enxergar.
  def imovel(codigo)
    { 'Codigo' => codigo, 'ImoCodigo' => codigo, 'Status' => 'ALUGUEL', 'Categoria' => 'Casa',
      'Dormitorios' => '3', 'Bairro' => 'Bairro Fictício', 'Cidade' => 'Cidade Fictícia',
      'ValorLocacao' => '2000', 'ValorVenda' => '0',
      'Foto' => { '1' => { 'Foto' => 'https://cdn.ficticio.invalid/1.jpg', 'Destaque' => 'Sim' },
                  '2' => { 'Foto' => 'https://cdn.ficticio.invalid/2.jpg', 'Destaque' => 'Nao' } } }
  end

  before do
    stub_request(:get, %r{acervo\.ficticio\.invalid/imoveis/listar})
      .to_return(status: 200, body: { '0' => imovel('4001'), 'total' => 1, 'paginas' => 1 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{acervo\.ficticio\.invalid/imoveis/detalhes})
      .to_return(status: 200, body: imovel('4002').to_json,
                 headers: { 'Content-Type' => 'application/json' })
    # O carrossel confere cada foto com HEAD antes de montar os cards (foto_aceita_pela_meta?).
    stub_request(:head, %r{\Ahttps://cdn\.ficticio\.invalid/})
      .to_return(status: 200, headers: { 'Content-Type' => 'image/jpeg' })
  end

  # CONTROLE POSITIVO. Sem ele, um cenário que barra tudo passaria no verde e ninguém veria
  # que a ferramenta parou de funcionar — o teste provaria só que ela não envia nada.
  it 'envia as fotos do código que a busca desta conversa devolveu' do
    passos = roteiro.executar([
                                { tool: 'buscar_imovel', args: { status_tipo: 'locacao', categoria: 'Casa' } },
                                { tool: 'enviar_fotos_imovel', args: { codigo: '4001' } }
                              ])

    expect(passos.last.resultado).to include('Enviei')
    expect(passos.last).to be_entregou_midia
  end

  # CENÁRIO NEGATIVO. O código existe no acervo — o `/imoveis/detalhes` responde com fotos —,
  # mas nenhuma busca desta conversa o devolveu. A trava tem que barrar ANTES de olhar o acervo.
  it 'não envia foto de código que a busca não devolveu, mesmo existindo no acervo' do
    passos = roteiro.executar([
                                { tool: 'buscar_imovel', args: { status_tipo: 'locacao', categoria: 'Casa' } },
                                { tool: 'enviar_fotos_imovel', args: { codigo: '4002' } }
                              ])

    expect(passos.last.resultado).to include('não apareceu na busca')
    expect(passos.last).not_to be_entregou_midia
  end

  # O achado da conv 19863, agora determinístico: a recusa é gravada como `status: ok`. Não é
  # bug a consertar aqui — é o motivo pelo qual nenhuma asserção deste harness pode se apoiar
  # no status para saber se a ação aconteceu. Se um dia o status passar a distinguir, este
  # exemplo fica vermelho e a asserção que depende dele é revista junto.
  it 'grava a recusa com status ok — o status não distingue envio de recusa' do
    passos = roteiro.executar([
                                { tool: 'buscar_imovel', args: { status_tipo: 'locacao', categoria: 'Casa' } },
                                { tool: 'enviar_fotos_imovel', args: { codigo: '4002' } }
                              ])

    expect(passos.last.status).to eq('ok')
    expect(passos.last).not_to be_entregou_midia
  end

  # A trava só EXISTE depois que uma busca registrou código (`vistos.any?`). Sem busca nenhuma
  # ela não roda — §16.1 da auditoria. Aqui o fato fica registrado de forma determinística; o
  # VERMELHO que cobra a correção é o acao_sem_trava_spec, e é lá que ele deve continuar,
  # sozinho. Duplicar o vermelho faria duas linhas falharem pelo mesmo defeito.
  it 'documenta o fail-open: sem busca alguma, a trava não é avaliada' do
    passos = roteiro.executar([{ tool: 'enviar_fotos_imovel', args: { codigo: '4002' } }])

    expect(passos.last).to be_entregou_midia
    expect(passos.last.resultado).to include('Enviei')
  end
end
# rubocop:enable RSpec/DescribeClass
