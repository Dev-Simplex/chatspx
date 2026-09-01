# Provides helper methods for working with Captain agent tools including
# tool resolution, text parsing, and metadata retrieval.
module Concerns::CaptainToolsHelpers
  extend ActiveSupport::Concern

  # Regular expression pattern for matching tool references in text.
  # Matches patterns like [Tool name](tool://tool_id) following markdown link syntax.
  TOOL_REFERENCE_REGEX = %r{\[[^\]]+\]\(tool://([^/)]+)\)}

  # Levantada quando um id de config/agents/tools.yml não tem classe correspondente.
  # Só sobe em test/development: em produção derrubar o boot por causa de uma tool seria
  # pior que a tool faltar, então lá o erro vira log (ver #load_agent_tools).
  class UnresolvableToolError < StandardError; end

  class_methods do
    # Returns all built-in agent tools with their metadata.
    # Only includes tools that have corresponding class files and can be resolved.
    #
    # @return [Array<Hash>] Array of tool hashes with :id, :title, :description, :icon
    def built_in_agent_tools
      @built_in_agent_tools ||= load_agent_tools
    end

    # Monta o nome de classe esperado para um id de tool.
    #
    # Usa `camelize`, NUNCA `classify`: `classify` singulariza a última palavra, então id no
    # plural (`apresentar_imoveis`, `listar_pecas`, `buscar_unidades`) procurava uma classe no
    # singular que não existe e a tool sumia em silêncio do registro. Regra única e sem exceção:
    # o nome do arquivo e o da classe seguem o id como ele está escrito no YAML.
    #
    # @param tool_id [String] The snake_case tool identifier
    # @return [String] The fully qualified class name expected for the tool
    def tool_class_name(tool_id)
      "Captain::Tools::#{tool_id.camelize}Tool"
    end

    # Resolves a tool class from a tool ID.
    # Converts snake_case tool IDs to PascalCase class names and constantizes them.
    #
    # @param tool_id [String] The snake_case tool identifier
    # @return [Class, nil] The tool class if found, nil if not resolvable
    def resolve_tool_class(tool_id)
      tool_class_name(tool_id).safe_constantize
    end

    # Returns an array of all built-in tool IDs.
    # Convenience method that extracts just the IDs from built_in_agent_tools.
    #
    # @return [Array<String>] Array of built-in tool IDs
    def built_in_tool_ids
      @built_in_tool_ids ||= built_in_agent_tools.map { |tool| tool[:id] }
    end

    private

    # Loads agent tools from the YAML configuration file.
    # Um id que não resolve para classe nenhuma levanta em test/development e é pulado (com log
    # de erro) em produção: ver #report_unresolvable_tool.
    #
    # @return [Array<Hash>] Array of resolvable tools with metadata
    # @api private
    def load_agent_tools
      tools_config = YAML.load_file(Rails.root.join('config/agents/tools.yml'))

      tools_config.filter_map do |tool_config|
        tool_id = tool_config['id']
        next report_unresolvable_tool(tool_id) unless resolve_tool_class(tool_id)

        { id: tool_id, title: tool_config['title'], description: tool_config['description'], icon: tool_config['icon'] }
      end
    end

    # Reage a um id do YAML que não resolve para classe nenhuma.
    #
    # Em test/development levanta: o descarte silencioso é justamente o bug que essa mudança
    # fecha, e quem renomeia uma tool tem que descobrir na hora, não meses depois pela tela.
    # Em produção NÃO pode levantar (uma tool quebrada derrubaria o app inteiro): mantém o
    # comportamento antigo de seguir sem ela, mas em `error` para aparecer no monitoramento.
    #
    # @param tool_id [String] The unresolvable tool identifier
    # @return [nil]
    # @api private
    def report_unresolvable_tool(tool_id)
      message = "Tool class not found for ID: #{tool_id} (esperava #{tool_class_name(tool_id)})"

      raise UnresolvableToolError, message if Rails.env.test? || Rails.env.development?

      Rails.logger.error message
      nil
    end
  end

  # Extracts tool IDs from text containing tool references.
  # Parses text for (tool://tool_id) patterns and returns unique tool IDs.
  #
  # @param text [String] Text to parse for tool references
  # @return [Array<String>] Array of unique tool IDs found in the text
  def extract_tool_ids_from_text(text)
    return [] if text.blank?

    tool_matches = text.scan(TOOL_REFERENCE_REGEX)
    tool_matches.flatten.uniq
  end
end
