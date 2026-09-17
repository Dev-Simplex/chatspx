require 'rails_helper'

RSpec.describe V2::Reports::AgentSummaryBuilder do
  let(:account) { create(:account) }
  let(:user1) { create(:user, account: account, role: :agent) }
  let(:user2) { create(:user, account: account, role: :agent) }

  let(:params) do
    {
      business_hours: business_hours,
      since: 1.week.ago.beginning_of_day,
      until: Time.current.end_of_day
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    context 'when there is team data' do
      before do
        c1 = create(:conversation, account: account, assignee: user1, created_at: Time.current)
        c2 = create(:conversation, account: account, assignee: user2, status: :resolved, created_at: Time.current)
        create(
          :reporting_event,
          account: account,
          conversation: c2,
          user: user2,
          name: 'conversation_resolved',
          value: 50,
          value_in_business_hours: 40,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'first_response',
          value: 20,
          value_in_business_hours: 10,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'reply_time',
          value: 30,
          value_in_business_hours: 15,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          conversation: c1,
          user: user1,
          name: 'reply_time',
          value: 40,
          value_in_business_hours: 25,
          created_at: Time.current
        )
      end

      context 'when business hours is disabled' do
        let(:business_hours) { false }

        it 'returns the correct team stats' do
          report = builder.build

          expect(report).to eq(
            [
              {
                id: user1.id,
                conversations_count: 1,
                resolved_conversations_count: 0,
                avg_resolution_time: nil,
                avg_first_response_time: 20.0,
                avg_first_response_time_after_assignment: nil,
                avg_reply_time: 35.0
              },
              {
                id: user2.id,
                conversations_count: 1,
                resolved_conversations_count: 1,
                avg_resolution_time: 50.0,
                avg_first_response_time: nil,
                avg_first_response_time_after_assignment: nil,
                avg_reply_time: nil
              }
            ]
          )
        end
      end

      context 'when business hours is enabled' do
        let(:business_hours) { true }

        it 'uses business hours values' do
          report = builder.build

          expect(report).to eq(
            [
              {
                id: user1.id,
                conversations_count: 1,
                resolved_conversations_count: 0,
                avg_resolution_time: nil,
                avg_first_response_time: 10.0,
                avg_first_response_time_after_assignment: nil,
                avg_reply_time: 20.0
              },
              {
                id: user2.id,
                conversations_count: 1,
                resolved_conversations_count: 1,
                avg_resolution_time: 40.0,
                avg_first_response_time: nil,
                avg_first_response_time_after_assignment: nil,
                avg_reply_time: nil
              }
            ]
          )
        end
      end
    end

    context 'when there is no team data' do
      let!(:new_user) { create(:user, account: account, role: :agent) }
      let(:business_hours) { false }

      it 'returns zero values' do
        report = builder.build

        expect(report).to include(
          {
            id: new_user.id,
            conversations_count: 0,
            resolved_conversations_count: 0,
            avg_resolution_time: nil,
            avg_first_response_time: nil,
            avg_first_response_time_after_assignment: nil,
            avg_reply_time: nil
          }
        )
      end
    end

    context 'when resolution events differ from the current conversation cohort' do
      let(:business_hours) { false }
      let(:inbox) { create(:inbox, account: account) }
      let(:other_inbox) { create(:inbox, account: account) }
      let(:prior_conversation) { create(:conversation, account: account, inbox: inbox, assignee: user1, status: :resolved, created_at: 2.weeks.ago) }
      let(:resolved_twice) { create(:conversation, account: account, inbox: inbox, assignee: user1, status: :resolved) }
      let(:reopened) { create(:conversation, account: account, inbox: inbox, assignee: user1) }
      let(:transferred) { create(:conversation, account: account, inbox: inbox, assignee: user2, status: :resolved) }
      let(:other_inbox_conversation) { create(:conversation, account: account, inbox: other_inbox, assignee: user1, status: :resolved) }

      before do
        [prior_conversation, resolved_twice, resolved_twice, reopened, transferred, other_inbox_conversation].each do |conversation|
          create(:reporting_event, account: account, inbox: conversation.inbox, conversation: conversation,
                                   user: user1, name: 'conversation_resolved', created_at: Time.current)
        end
      end

      it 'excludes conversations created before the period even when resolved within it' do
        stats = builder.build.find { |row| row[:id] == user1.id }

        expect(stats).to include(conversations_count: 3, resolved_conversations_count: 2)
      end

      it 'counts a conversation resolved twice only once' do
        stats = builder.build.find { |row| row[:id] == user1.id }

        expect(stats[:resolved_conversations_count]).to eq(2)
      end

      it 'excludes a conversation that is currently open' do
        stats = builder.build.find { |row| row[:id] == user1.id }

        expect(stats[:resolved_conversations_count]).to be < stats[:conversations_count]
      end

      it 'attributes a transferred conversation to its current assignee' do
        stats = builder.build.find { |row| row[:id] == user2.id }

        expect(stats).to include(conversations_count: 1, resolved_conversations_count: 1)
      end

      it 'applies the inbox filter to both counts' do
        scoped_builder = described_class.new(account: account, params: params.merge(inbox_id: inbox.id))
        stats = scoped_builder.build.find { |row| row[:id] == user1.id }

        expect(stats).to include(conversations_count: 2, resolved_conversations_count: 1)
      end

      it 'never reports more resolutions than conversations for any agent' do
        expect(builder.build).to all(satisfy { |row| row[:resolved_conversations_count] <= row[:conversations_count] })
      end
    end
  end
end
