require 'rails_helper'

# Invariante do REGISTRO de tools, não do comportamento de nenhuma tool específica.
#
# O bug que este arquivo existe pra impedir: `config/agents/tools.yml` listava 29 tools e só 27
# chegavam na tela. `resolve_tool_class` usava `classify`, que singulariza a última palavra, então
# `apresentar_imoveis` procurava `ApresentarImoveiTool` e `listar_pecas` procurava `ListarPecaTool`.
# Nenhuma das duas existia, `load_agent_tools` descartava com um `Rails.logger.warn` e ninguém via.
#
# Spec de tool isolada NÃO pega isso: já existia
# spec/enterprise/lib/captain/tools/apresentar_imoveis_tool_spec.rb, passando verde, com a tool
# morta há meses: ele referencia a classe pela constante e nunca passa pelo registro.
RSpec.describe 'Registro de tools do Captain', type: :model do
  let(:tools_config) { YAML.load_file(Rails.root.join('config/agents/tools.yml')) }
  let(:configured_ids) { tools_config.map { |tool| tool['id'] } }

  describe 'config/agents/tools.yml' do
    it 'resolve todo id para uma classe que existe de verdade' do
      quebrados = configured_ids.reject { |id| Captain::Assistant.resolve_tool_class(id) }.map do |id|
        "#{id.inspect} => esperava #{Captain::Assistant.tool_class_name(id)} " \
          "(arquivo enterprise/lib/captain/tools/#{id}_tool.rb), que não existe"
      end

      expect(quebrados).to be_empty, <<~MSG
        #{quebrados.size} id(s) de config/agents/tools.yml não resolvem para classe nenhuma:

        #{quebrados.map { |linha| "  - #{linha}" }.join("\n")}

        A tool não some com erro: ela é descartada do registro e simplesmente não aparece na tela
        de Agentes IA. O nome da classe e do arquivo tem que seguir o id palavra por palavra,
        plural incluído. Se o id mudou, renomeie a classe e o arquivo junto (e vice-versa).
      MSG
    end

    it 'entrega ao front exatamente as tools declaradas, sem descarte silencioso' do
      expect(Captain::Assistant.built_in_tool_ids).to eq(configured_ids)
    end

    it 'não tem id repetido nem em branco' do
      expect(configured_ids).to all(be_present)
      expect(configured_ids).to eq(configured_ids.uniq)
    end

    it 'declara título, descrição e ícone em toda tool' do
      incompletas = tools_config.reject { |tool| tool.values_at('title', 'description', 'icon').all?(&:present?) }

      expect(incompletas.map { |tool| tool['id'] }).to be_empty
    end
  end

  describe 'id no plural' do
    # Regressão direta das três vítimas do `classify`: as duas que estavam mortas
    # (`apresentar_imoveis`, `listar_pecas`) e a que só funcionava porque a classe tinha sido
    # batizada no singular pra contornar o bug (`buscar_unidades`).
    %w[apresentar_imoveis listar_pecas buscar_unidades].each do |id|
      it "resolve #{id} para a classe no plural" do
        expect(Captain::Assistant.resolve_tool_class(id)).to eq("Captain::Tools::#{id.camelize}Tool".constantize)
      end
    end
  end

  describe 'id que não resolve' do
    let(:registry) do
      Class.new do
        include Concerns::CaptainToolsHelpers

        def self.name
          'RegistryTestClass'
        end
      end
    end

    before do
      allow(YAML).to receive(:load_file).and_return(
        [{ 'id' => 'tool_que_nao_existe', 'title' => 'X', 'description' => 'X', 'icon' => 'x' }]
      )
    end

    it 'levanta em test, dizendo qual id falhou e que classe faltou' do
      expect { registry.built_in_agent_tools }.to raise_error(
        Concerns::CaptainToolsHelpers::UnresolvableToolError,
        /tool_que_nao_existe.*Captain::Tools::ToolQueNaoExisteTool/
      )
    end

    it 'levanta em development pelo mesmo motivo' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

      expect { registry.built_in_agent_tools }.to raise_error(Concerns::CaptainToolsHelpers::UnresolvableToolError)
    end

    it 'em produção NÃO levanta: loga error e segue sem a tool' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(Rails.logger).to receive(:error)

      expect(registry.built_in_agent_tools).to be_empty
      expect(Rails.logger).to have_received(:error).with(/tool_que_nao_existe/)
    end
  end
end
