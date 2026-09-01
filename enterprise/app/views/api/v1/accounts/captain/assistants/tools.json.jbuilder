# `available_agent_tools` junta as tools de sistema (tools.yml) com as personalizadas da
# conta, e so as personalizadas trazem `custom: true` (Captain::CustomTool#to_tool_metadata).
# Sem serializar essa flag, o filtro `!tool.custom` da tela de Ferramentas nunca excluia
# nada e toda tool personalizada habilitada aparecia duas vezes: no catalogo de sistema e
# na lista de personalizadas.
json.array! @tools do |tool|
  json.id tool[:id]
  json.title tool[:title]
  json.description tool[:description]
  json.icon tool[:icon]
  json.custom tool[:custom].present?
end
