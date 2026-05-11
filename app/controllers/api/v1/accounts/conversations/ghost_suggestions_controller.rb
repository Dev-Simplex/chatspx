class Api::V1::Accounts::Conversations::GhostSuggestionsController < Api::V1::Accounts::Conversations::BaseController
  def create
    detected_language = Copilot::LanguageDetectorService.new(
      conversation: @conversation, account: Current.account
    ).perform
    suggestion = Copilot::GhostSuggestionService.new(
      conversation: @conversation,
      account: Current.account,
      language: detected_language
    ).perform
    render json: { suggestion: suggestion, language: detected_language }
  end
end
