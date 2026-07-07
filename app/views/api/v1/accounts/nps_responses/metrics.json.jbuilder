# Métricas de NPS. O cálculo é fonte única em Reports::NpsCalculator (@metrics);
# aqui só serializamos. status_count/blocked/signals vêm do controller.
json.total_count @metrics[:total_count]
json.total_sent_count @metrics[:sent_count]
json.scores_count @metrics[:scores_count]
json.promoters_count @metrics[:promoters_count]
json.passives_count @metrics[:passives_count]
json.detractors_count @metrics[:detractors_count]
json.promoters_pct @metrics[:promoters_pct]
json.passives_pct @metrics[:passives_pct]
json.detractors_pct @metrics[:detractors_pct]
json.nps_score @metrics[:nps_score]
json.response_rate @metrics[:response_rate]

# Guarda de amostra: reliable=false abaixo de min_sample respostas.
json.reliable @metrics[:reliable]
json.min_sample @metrics[:min_sample]

# Tendência: delta em PONTOS de NPS vs período anterior (nil se sem base).
json.previous_nps_score @metrics[:previous_nps_score]
json.nps_delta @metrics[:nps_delta]

json.status_count @status_count
json.blocked_count @blocked_count
json.blocked_by_label_count @blocked_by_label_count

# Closing the loop: tempo medio de follow-up humano ao detrator + fila aguardando.
json.detractor_followup @detractor_followup

json.signals @signals
