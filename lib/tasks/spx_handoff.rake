# Roteamento do handoff por conta (dinâmico). Dois modos:
#   - TIME FIXO: todo handoff cai num time só (ex.: recepção), que distribui na mão.
#   - IA DECIDE (default): a IA roteia pelo assunto (time do setor / team_id).
# Guardado em account.custom_attributes['handoff_team_id'] (setado = fixo; ausente = IA decide).
#
#   bundle exec rails "spx:handoff:route[6,60]"     # conta 6 -> time fixo 60 (recepção)
#   bundle exec rails "spx:handoff:route[6,ia]"     # conta 6 -> IA decide (limpa o override)
#   bundle exec rails "spx:handoff:show[6]"
namespace :spx do
  namespace :handoff do
    desc 'Define o roteamento do handoff da conta: <team_id> pra time fixo, ou "ia"/"off" pra IA decidir'
    task :route, %i[account_id team_id] => :environment do |_t, args|
      acc = Account.find(args[:account_id].to_i)
      ca = acc.custom_attributes || {}
      arg = args[:team_id].to_s.strip.downcase

      if arg.blank? || %w[ia off none nil setor].include?(arg)
        acc.update!(custom_attributes: ca.except('handoff_team_id'))
        puts "conta #{acc.id}: handoff = IA DECIDE o time (roteia por setor)."
      else
        tid = arg.to_i
        team = acc.teams.find_by(id: tid)
        abort "time #{tid} nao existe na conta #{acc.id}" if team.nil?
        acc.update!(custom_attributes: ca.merge('handoff_team_id' => tid))
        puts "conta #{acc.id}: handoff = TIME FIXO #{tid} (#{team.name}). Membros: #{team.members.pluck(:id, :name).inspect}"
      end
    end

    desc 'Mostra o roteamento de handoff da conta'
    task :show, %i[account_id] => :environment do |_t, args|
      acc = Account.find(args[:account_id].to_i)
      tid = acc.custom_attributes&.dig('handoff_team_id')
      if tid.present?
        team = acc.teams.find_by(id: tid)
        puts "conta #{acc.id}: TIME FIXO #{tid} (#{team&.name}) — a recepção/humano distribui na mão."
      else
        puts "conta #{acc.id}: IA DECIDE o time (roteia por setor). [default]"
      end
    end
  end
end
