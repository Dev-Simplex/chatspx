require 'rails_helper'

# Bloco 3.03 — o perfil resolvido em flags planas (lista canonica: `22-plano-widget.md` §B.3).
RSpec.describe WidgetProfile do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  describe '.resolve' do
    it 'returns exactly the eleven canonical flags, and they are flat' do
      resolved = described_class.resolve(web_widget)

      expect(resolved.keys).to match_array(
        %w[showKnowledgeBase showConversationList teaserEnabled teaserDelayMs teaserScrollPercent
           captureFlow primaryExit csatOnResolve emailContinuity homeLayout aiLabelPersistent]
      )
      expect(resolved.values.none? { |value| value.is_a?(Hash) || value.is_a?(Array) }).to be(true)
    end

    it 'accepts the channel or the inbox and answers the same thing' do
      expect(described_class.resolve(web_widget)).to eq(described_class.resolve(inbox))
    end

    it 'reads an inbox without a profile as support — the behaviour of today (A4)' do
      expect(inbox.widget_profile).to be_nil

      resolved = described_class.resolve(inbox)

      expect(resolved['homeLayout']).to eq('support')
      expect(resolved['showKnowledgeBase']).to be(true)
      expect(resolved['teaserEnabled']).to be(false)
      expect(resolved['primaryExit']).to eq('none')
    end

    it 'resolves the marketing profile to capture' do
      inbox.update!(widget_profile: 'marketing')

      resolved = described_class.resolve(inbox)

      expect(resolved['homeLayout']).to eq('marketing')
      expect(resolved['showKnowledgeBase']).to be(false)
      expect(resolved['showConversationList']).to be(false)
      expect(resolved['teaserEnabled']).to be(true)
      expect(resolved['primaryExit']).to eq('whatsapp')
    end

    it 'carries the composite teaser trigger: 8 s and 30%' do
      resolved = described_class.resolve(inbox)

      expect(resolved['teaserDelayMs']).to eq(8000)
      expect(resolved['teaserScrollPercent']).to eq(30)
    end

    describe 'the stored value always wins over the profile (A3, regime 2)' do
      # E o aceite literal do bloco 3.03.
      it 'keeps CSAT off on a support inbox that has csat_survey_enabled: false' do
        inbox.update!(csat_survey_enabled: false, widget_profile: 'support')

        expect(described_class.resolve(inbox)['csatOnResolve']).to be(false)
      end

      it 'keeps CSAT on when the column says so, whatever the profile' do
        inbox.update!(csat_survey_enabled: true, widget_profile: 'marketing')

        expect(described_class.resolve(inbox)['csatOnResolve']).to be(true)
      end

      it 'mirrors continuity_via_email from the channel column' do
        web_widget.update!(continuity_via_email: false)

        expect(described_class.resolve(inbox.reload)['emailContinuity']).to be(false)
      end

      it 'only calls the flow conversational when the pre-chat form is actually enabled' do
        web_widget.update!(pre_chat_form_enabled: false)
        inbox.update!(widget_profile: 'marketing')
        expect(described_class.resolve(inbox.reload)['captureFlow']).to eq('form')

        web_widget.update!(pre_chat_form_enabled: true)
        expect(described_class.resolve(inbox.reload)['captureFlow']).to eq('conversational')
      end

      it 'keeps the classic form on support even with the pre-chat enabled' do
        web_widget.update!(pre_chat_form_enabled: true)
        inbox.update!(widget_profile: 'support')

        expect(described_class.resolve(inbox.reload)['captureFlow']).to eq('form')
      end
    end
  end

  describe '.seed_defaults — regime 1 de A3: so na criacao, e so o que nasce agora' do
    it 'seeds widget_triggers on a new inbox created with a profile' do
      created = create(:inbox, account: account, additional_attributes: { 'widget_profile' => 'marketing' })

      expect(created.widget_triggers).to eq(
        { 'version' => 1, 'enabled' => true, 'approach' => 'bold',
          'approach_mobile' => 'bold', 'degrade_on_return' => true }
      )
    end

    it 'seeds the triggers disabled on a support inbox — the bubble stays silent' do
      created = create(:inbox, account: account, additional_attributes: { 'widget_profile' => 'support' })

      expect(created.widget_triggers['enabled']).to be(false)
    end

    it 'does not seed anything on an inbox created without a profile' do
      created = create(:inbox, account: account)

      expect(created.additional_attributes).to eq({})
    end

    it 'never overwrites triggers that came in the same request' do
      sent = { 'version' => 1, 'approach' => 'discreet' }
      created = create(:inbox, account: account,
                               additional_attributes: { 'widget_profile' => 'marketing', 'widget_triggers' => sent })

      expect(created.widget_triggers).to eq(sent)
    end

    it 'does NOT touch columns that already exist — the profile proposes, it never rewrites' do
      created = create(:inbox, account: account, csat_survey_enabled: false,
                               additional_attributes: { 'widget_profile' => 'support' })

      expect(created.csat_survey_enabled).to be(false)
    end

    it 'does not re-seed on a later update — seeding is a creation-time act only' do
      created = create(:inbox, account: account)
      created.update!(widget_profile: 'marketing')

      expect(created.reload.widget_triggers).to be_nil
    end
  end
end
