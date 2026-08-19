# 6.05 — o resultado do teste A/B. Tudo aqui vem do Flows::AbReportService, que le
# `tracking_events`; a view nao calcula nada, so publica.
#
# `comparisons` NUNCA e omitido quando ha mais de uma variante, e `verdict` pode valer
# `inconclusivo` — e ele que carrega o aceite "o teste declara quando a diferenca ainda nao
# e distinguivel do acaso". A tela deve mostrar o motivo (`reason`), nao esconder a linha.
json.experiment @report['experiment']
json.variants @report['variants']
json.comparisons @report['comparisons']
