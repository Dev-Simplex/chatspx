require 'rails_helper'

describe Events::Types do
  describe 'PR B7 scaffolding constants' do
    # As constantes abaixo sao declaradas pela PR B7 para garantir que os nomes
    # de evento existam no namespace antes que os handlers reais sejam
    # implementados nas PRs B1 (reactions), B4 (user settings) e G1 (pins).
    # O ActionCableListener mantem stubs no-op para esses eventos enquanto a
    # logica nao for conectada, preservando o comportamento atual do webapp Vue.

    context 'with message reaction events (handlers em PR B1)' do
      it 'defines MESSAGE_REACTION_ADDED with the expected value' do
        expect(described_class::MESSAGE_REACTION_ADDED).to eq('message.reaction_added')
      end

      it 'defines MESSAGE_REACTION_REMOVED with the expected value' do
        expect(described_class::MESSAGE_REACTION_REMOVED).to eq('message.reaction_removed')
      end
    end

    context 'with conversation user setting event (handler em PR B4)' do
      it 'defines CONVERSATION_USER_SETTING_CHANGED with the expected value' do
        expect(described_class::CONVERSATION_USER_SETTING_CHANGED).to eq('conversation.user_setting_changed')
      end
    end

    context 'with conversation pin events (handlers em PR G1)' do
      it 'defines CONVERSATION_PIN_ADDED with the expected value' do
        expect(described_class::CONVERSATION_PIN_ADDED).to eq('conversation.pin_added')
      end

      it 'defines CONVERSATION_PIN_REMOVED with the expected value' do
        expect(described_class::CONVERSATION_PIN_REMOVED).to eq('conversation.pin_removed')
      end
    end

    it 'exposes all five PR B7 constants on the module' do
      expected_constants = %i[
        MESSAGE_REACTION_ADDED
        MESSAGE_REACTION_REMOVED
        CONVERSATION_USER_SETTING_CHANGED
        CONVERSATION_PIN_ADDED
        CONVERSATION_PIN_REMOVED
      ]
      expect(described_class.constants & expected_constants).to match_array(expected_constants)
    end
  end
end
