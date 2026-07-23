#!/usr/bin/env bash
# Gera links de login DIRETO (SSO) para testar com vários usuários ao mesmo tempo.
#
# Por que existe: testar a feature "Puxar Atendimento" exige 2 pessoas ao mesmo
# tempo (quem pede e quem aprova). Ficar deslogando/logando atrapalha — com estes
# links você entra como cada um em janelas anônimas diferentes, lado a lado.
#
# ATENÇÃO: cada token vale 5 MINUTOS e é de USO ÚNICO (some ao logar). Rode este
# script na HORA de testar; link velho não funciona. É por isso que ele existe em
# vez de uma lista fixa de links.
#
# Uso:
#   ./task/links-agentes-teste.sh                      # os 3 padrão (A, B, admin)
#   ./task/links-agentes-teste.sh fulano@empresa.com   # um e-mail específico
#   ./task/links-agentes-teste.sh a@x.com b@y.com      # vários
#
# Alternativa SEM terminal: painel de super admin →
#   https://nicolas.chatspx.app/super_admin  → Users → (usuário) → "Impersonate user"
set -euo pipefail
cd "$(dirname "$0")/.."

EMAILS="$*"

RAILS_ENV=production EMAILS="$EMAILS" bundle exec rails runner '
emails = ENV.fetch("EMAILS", "").split(/[\s,]+/).reject(&:empty?)

alvos =
  if emails.any?
    emails.map { |e| [User.find_by(email: e), e] }
  else
    # padrão: o trio do cenário de teste da feature
    [[10, "Agente Teste A  (SOLICITANTE — pede a conversa)"],
     [11, "Agente Teste B  (DONO — aprova ou nega)"],
     [1,  "admin           (força atribuição / vê tudo)"]]
      .map { |id, rotulo| [User.find_by(id: id), rotulo] }
  end

puts ""
puts "Links válidos por 5 MINUTOS, uso único. Abra cada um numa janela anônima."
puts ""
alvos.each do |user, rotulo|
  if user.nil?
    puts "#{rotulo}"
    puts "  (usuário não encontrado)"
  else
    puts "#{rotulo} <#{user.email}>"
    puts "  #{user.generate_sso_link}"
  end
  puts ""
end
' 2>/dev/null | grep -vE "RubyLLM|deprecated|migration guide|dotenv|ip_lookup|^I, |^W, " || true
