class Messages::TranslateService
  pattr_initialize [:message!, :target_language!]

  def perform
    return nil if already_translated?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: @message,
      target_language: @target_language
    ).perform

    persist_translation(translated_content) if translated_content.present?
    translated_content
  end

  private

  def already_translated?
    @message.translations.present? && @message.translations[@target_language].present?
  end

  def persist_translation(translated_content)
    translations = (@message.translations.presence || {}).merge(@target_language => translated_content)
    @message.update!(translations: translations)
  end
end
