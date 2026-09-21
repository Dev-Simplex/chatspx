# Grava chaves em `attachments.meta` sem apagar as que outro job gravou no meio-tempo.
#
# Tres jobs escrevem no mesmo jsonb, todos na fila `low` e disparados pelo mesmo after_create_commit: a
# onda (Audio::WaveformGenerationJob), a transcricao OSS (AudioTranscriptionService) e a Enterprise
# (Messages::AudioTranscriptionService). Cada um lia o meta, trabalhava por segundos e gravava o meta LIDO
# ANTES — a onda apagava a transcricao, e a transcricao Enterprise (que substituia o jsonb inteiro) apagava
# a onda. Aqui a mescla acontece no banco, numa instrucao so (`||` do jsonb): a ordem deixa de importar.
module Attachments::MetaMerge
  def self.call(attachment, chaves)
    Attachment.where(id: attachment.id)
              .update_all(["meta = COALESCE(meta, '{}'::jsonb) || ?::jsonb", chaves.stringify_keys.to_json]) # rubocop:disable Rails/SkipsModelValidations
  end
end
