#!/usr/bin/env bash
# Gera links de login DIRETO (SSO) para os agentes de teste do staging.
#
# Por que existe: testar a feature "Puxar Atendimento" exige 2 pessoas ao mesmo
# tempo (quem pede e quem aprova). Ficar deslogando/logando atrapalha — com estes
# links você entra como cada um em janelas anônimas diferentes, lado a lado.
#
# ATENÇÃO: cada token vale 5 MINUTOS e é de USO ÚNICO (some ao logar). Rode este
# script na hora de testar; links velhos não funcionam. É por isso que ele existe
# em vez de uma lista fixa de links.
#
# Uso:  ./task/links-agentes-teste.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RAILS_ENV=production bundle exec rails runner '
usuarios = [
  [10, "Agente Teste A  (SOLICITANTE — pede a conversa)"],
  [11, "Agente Teste B  (DONO — aprova ou nega)"],
  [1,  "admin           (força atribuição / vê tudo)"]
]
puts ""
puts "Links válidos por 5 MINUTOS, uso único. Abra cada um numa janela anônima."
puts ""
usuarios.each do |id, rotulo|
  u = User.find_by(id: id)
  next puts("#{rotulo}\n  (usuário #{id} não existe mais)\n\n") unless u

  puts rotulo
  puts "  #{u.generate_sso_link}"
  puts ""
end
' 2>/dev/null | grep -vE "RubyLLM|deprecated|migration guide|dotenv|ip_lookup|^I, |^W, |^\s*$" || true
echo ""
