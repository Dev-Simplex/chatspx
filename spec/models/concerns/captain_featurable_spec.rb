# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaptainFeaturable do
  let(:account) { create(:account) }
  # Features que continuam opt-in (chave ausente = desligada).
  let(:opt_in_features) { Llm::Models.feature_keys - CaptainFeaturable::DEFAULT_ON_FEATURES }

  describe 'dynamic method generation' do
    it 'generates enabled? methods for all features' do
      Llm::Models.feature_keys.each do |feature_key|
        expect(account).to respond_to("captain_#{feature_key}_enabled?")
      end
    end

    it 'generates model accessor methods for all features' do
      Llm::Models.feature_keys.each do |feature_key|
        expect(account).to respond_to("captain_#{feature_key}_model")
      end
    end
  end

  describe 'feature enabled methods' do
    context 'when no features are explicitly enabled' do
      it 'returns false for the opt-in features' do
        opt_in_features.each do |feature_key|
          expect(account.send("captain_#{feature_key}_enabled?")).to be(false), "esperava #{feature_key} desligada"
        end
      end

      it 'keeps the default-on features enabled' do
        CaptainFeaturable::DEFAULT_ON_FEATURES.each do |feature_key|
          expect(account.send("captain_#{feature_key}_enabled?")).to be(true), "esperava #{feature_key} ligada"
        end
      end
    end

    context 'when features are explicitly enabled' do
      before do
        account.update!(captain_features: { 'editor' => true, 'assistant' => true })
      end

      it 'returns true for enabled features' do
        expect(account.captain_editor_enabled?).to be true
        expect(account.captain_assistant_enabled?).to be true
      end

      it 'returns false for disabled features' do
        expect(account.captain_copilot_enabled?).to be false
      end
    end

    context 'when captain_features is nil' do
      before do
        account.update!(captain_features: nil)
      end

      it 'returns false for the opt-in features' do
        opt_in_features.each do |feature_key|
          expect(account.send("captain_#{feature_key}_enabled?")).to be(false), "esperava #{feature_key} desligada"
        end
      end

      it 'keeps the default-on features enabled' do
        CaptainFeaturable::DEFAULT_ON_FEATURES.each do |feature_key|
          expect(account.send("captain_#{feature_key}_enabled?")).to be(true), "esperava #{feature_key} ligada"
        end
      end
    end
  end

  # O gate de label_suggestion nasceu DEPOIS do recurso: ate aqui Captain::TasksPolicy
  # devolvia `true` fixo e a sugestao de rotulos rodava em toda conta. Por isso chave
  # AUSENTE precisa continuar significando LIGADO; so o `false` gravado desliga.
  describe 'label_suggestion (default preservador)' do
    it 'is enabled when the key is absent' do
      account.update!(captain_features: { 'editor' => true })

      expect(account.captain_label_suggestion_enabled?).to be true
    end

    it 'is disabled when the stored value is false' do
      account.update!(captain_features: { 'label_suggestion' => false })

      expect(account.captain_label_suggestion_enabled?).to be false
    end

    it 'is enabled when the stored value is true' do
      account.update!(captain_features: { 'label_suggestion' => true })

      expect(account.captain_label_suggestion_enabled?).to be true
    end
  end

  # O gate de verdade da transcricao mora em settings['audio_transcriptions'] (plural),
  # que e o que Attachment e Messages::AudioTranscriptionService leem.
  describe 'audio_transcription (gate externo)' do
    it 'reads the real gate instead of captain_features' do
      account.update!(audio_transcriptions: true, captain_features: {})

      expect(account.captain_audio_transcription_enabled?).to be true
    end

    it 'ignores a stale copy left inside captain_features' do
      account.update!(audio_transcriptions: false, captain_features: { 'audio_transcription' => true })

      expect(account.captain_audio_transcription_enabled?).to be false
    end

    it 'is disabled when neither key was ever set' do
      expect(account.captain_audio_transcription_enabled?).to be false
    end
  end

  describe '#apply_captain_features' do
    it 'writes audio_transcription to the real gate, never to captain_features' do
      account.apply_captain_features('audio_transcription' => true)
      account.save!
      account.reload

      expect(account.audio_transcriptions).to be true
      expect(account.captain_features).not_to have_key('audio_transcription')
    end

    it 'merges into the stored features without dropping the others' do
      account.update!(captain_features: { 'editor' => true })

      account.apply_captain_features('label_suggestion' => false)
      account.save!

      expect(account.reload.captain_features).to eq({ 'editor' => true, 'label_suggestion' => false })
    end

    it 'clears the orphan audio_transcription copy on any write' do
      account.update!(captain_features: { 'audio_transcription' => true, 'editor' => true })

      account.apply_captain_features('editor' => false)
      account.save!

      expect(account.reload.captain_features).to eq({ 'editor' => false })
    end
  end

  describe 'model accessor methods' do
    context 'when no models are explicitly configured' do
      it 'returns default models for all features' do
        Llm::Models.feature_keys.each do |feature_key|
          expected_default = Llm::Models.default_model_for(feature_key)
          expect(account.send("captain_#{feature_key}_model")).to eq(expected_default)
        end
      end
    end

    context 'when models are explicitly configured' do
      before do
        account.update!(captain_models: {
                          'editor' => 'gpt-4.1-mini',
                          'assistant' => 'gpt-5',
                          'label_suggestion' => 'gpt-4.1-nano'
                        })
      end

      it 'returns configured models for configured features' do
        expect(account.captain_editor_model).to eq('gpt-4.1-mini')
        expect(account.captain_assistant_model).to eq('gpt-5')
        expect(account.captain_label_suggestion_model).to eq('gpt-4.1-nano')
      end

      it 'returns default models for unconfigured features' do
        expect(account.captain_copilot_model).to eq(Llm::Models.default_model_for('copilot'))
        expect(account.captain_audio_transcription_model).to eq(Llm::Models.default_model_for('audio_transcription'))
      end
    end

    context 'when configured with invalid model' do
      before do
        account.captain_models = { 'editor' => 'invalid-model' }
      end

      it 'falls back to default model' do
        expect(account.captain_editor_model).to eq(Llm::Models.default_model_for('editor'))
      end
    end

    context 'when captain_models is nil' do
      before do
        account.update!(captain_models: nil)
      end

      it 'returns default models for all features' do
        Llm::Models.feature_keys.each do |feature_key|
          expected_default = Llm::Models.default_model_for(feature_key)
          expect(account.send("captain_#{feature_key}_model")).to eq(expected_default)
        end
      end
    end
  end

  describe 'integration with existing captain_preferences' do
    it 'enabled? methods use the same logic as captain_preferences[:features]' do
      account.update!(captain_features: { 'editor' => true, 'copilot' => true })
      prefs = account.captain_preferences

      Llm::Models.feature_keys.each do |feature_key|
        expect(account.send("captain_#{feature_key}_enabled?")).to eq(prefs[:features][feature_key])
      end
    end

    it 'model methods use the same logic as captain_preferences[:models]' do
      account.update!(captain_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5' })
      prefs = account.captain_preferences

      Llm::Models.feature_keys.each do |feature_key|
        expect(account.send("captain_#{feature_key}_model")).to eq(prefs[:models][feature_key])
      end
    end
  end
end
