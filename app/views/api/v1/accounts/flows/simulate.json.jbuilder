# SIMULAÇÃO (dry-run) — o caminho que o fluxo SEGUIRIA sem efetivar nada. `steps` é a lista
# ORDENADA dos nós percorridos (cada um com o que faria e, em condition/router, o ramo tomado);
# `branch_path` são só as decisões, na ordem. `conversation` é a amostra usada (só pra a UI
# mostrar contra quem simulou). Ver Flows::SimulationService / Flows::SimulationWalk.
json.steps @simulation.steps
json.branch_path @simulation.branch_path
json.conversation do
  json.id @conversation.display_id
  json.contact_name @conversation.contact&.name
end
