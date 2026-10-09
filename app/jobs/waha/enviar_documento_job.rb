# MIDIA-01: o video acima de 16 MB sai pelo /api/sendFile, e o WAHA so responde depois de baixar o arquivo (ate
# 100 MB, timeout de 300 s). Por isso o envio roda aqui, na fila medium, e nao dentro do EventDispatcherJob da
# fila critical, que distribui os eventos de todas as mensagens.
class Waha::EnviarDocumentoJob < ApplicationJob
  queue_as :medium

  def perform(message_id)
    message = Message.find_by(id: message_id)
    Waha::OutboundSpecialMessageService.new(message).perform if message
  end
end
