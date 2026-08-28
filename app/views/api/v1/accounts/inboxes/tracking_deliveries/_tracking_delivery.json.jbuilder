# A lista FECHADA de colunas do log de rastreio. O que nao esta escrito aqui nao sai.
#
# As duas ausencias que importam, e sao ausencias de proposito:
#  · `tracking_event.properties` — e onde os VALORES do evento moram. `field_names` abaixo
#    diz QUAIS campos foram enviados; `properties` diria o que havia dentro deles.
#  · qualquer coisa vinda de `TrackingCredential` — este controller nem consulta a tabela.
#
# `emq` sai por `to_f` e nao cru: a coluna e `decimal(3,1)`, e um BigDecimal vira a STRING
# "9.2" no JSON. O painel filtra por `typeof valor === 'number'` antes de calcular a media
# (`useTrackingDiagnostics.js`), entao a string seria descartada em silencio e o EMQ medio
# apareceria vazio com o banco cheio.
json.event_id delivery.tracking_event&.event_id
json.name delivery.tracking_event&.name
json.destination delivery.destination
json.status delivery.status
json.http_status delivery.http_status
json.error_code delivery.error_code
json.error_message delivery.error_message
json.emq delivery.emq&.to_f
json.attempts delivery.attempts
json.last_attempted_at delivery.last_attempted_at
json.field_names delivery.field_names
