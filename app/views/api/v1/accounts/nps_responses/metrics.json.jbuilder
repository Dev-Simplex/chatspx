json.total_count @total_count
json.scores_count @scores_count
json.status_count @status_count
json.promoters_count @promoters_count
json.passives_count @passives_count
json.detractors_count @detractors_count
json.total_sent_count @total_sent_count
json.average_response_delay_seconds @average_response_delay_seconds
json.fastest_response_delay_seconds @fastest_response_delay_seconds
json.slowest_response_delay_seconds @slowest_response_delay_seconds

# Calculate NPS score
total_responded = @promoters_count + @passives_count + @detractors_count
if total_responded > 0
  promoters_percentage = (@promoters_count.to_f / total_responded * 100).round(2)
  detractors_percentage = (@detractors_count.to_f / total_responded * 100).round(2)
  nps_score = (promoters_percentage - detractors_percentage).round(2)
else
  nps_score = 0
end

json.nps_score nps_score
json.response_rate total_responded > 0 && @total_sent_count > 0 ? ((total_responded.to_f / @total_sent_count) * 100).round(2) : 0
json.blocked_count @blocked_count
json.blocked_by_label_count @blocked_by_label_count
json.scores_count @scores_count
