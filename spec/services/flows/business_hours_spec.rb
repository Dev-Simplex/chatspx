# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::BusinessHours do
  let(:account) { create(:account) }
  # O after_create do inbox semeia o expediente padrão: Seg–Sex 09:00–17:00, Dom+Sáb fechados.
  let(:inbox) { create(:inbox, account: account, timezone: 'UTC') }

  # Datas âncora (confirmadas): 11/07/2026 = Sábado, 13/07 = Segunda, 14/07 = Terça,
  # 17/07 = Sexta, 20/07 = Segunda.
  describe '.next_opening' do
    context 'when working hours are NOT enabled (no-op)' do
      it 'returns the original instant untouched' do
        from = Time.zone.parse('2026-07-11 15:00 UTC') # Saturday, off-hours — but disabled
        expect(described_class.next_opening(inbox, from: from)).to eq(from)
      end
    end

    context 'when working hours are enabled (default Mon–Fri 09:00–17:00 UTC)' do
      before { inbox.update!(working_hours_enabled: true) }

      it 'pushes a weekend instant to Monday 09:00' do
        from = Time.zone.parse('2026-07-11 15:00 UTC') # Saturday
        expect(described_class.next_opening(inbox, from: from)).to eq(Time.zone.parse('2026-07-13 09:00 UTC'))
      end

      it 'pushes a pre-open weekday instant to the same-day 09:00' do
        from = Time.zone.parse('2026-07-13 06:00 UTC') # Monday, before opening
        expect(described_class.next_opening(inbox, from: from)).to eq(Time.zone.parse('2026-07-13 09:00 UTC'))
      end

      it 'leaves an instant already inside business hours unchanged' do
        from = Time.zone.parse('2026-07-13 10:00 UTC') # Monday mid-morning
        expect(described_class.next_opening(inbox, from: from)).to eq(from)
      end

      it 'pushes an after-close weekday instant to the next day 09:00' do
        from = Time.zone.parse('2026-07-13 18:00 UTC') # Monday evening
        expect(described_class.next_opening(inbox, from: from)).to eq(Time.zone.parse('2026-07-14 09:00 UTC'))
      end

      it 'skips the weekend: a Friday-after-close instant lands on Monday 09:00' do
        from = Time.zone.parse('2026-07-17 18:00 UTC') # Friday evening
        expect(described_class.next_opening(inbox, from: from)).to eq(Time.zone.parse('2026-07-20 09:00 UTC'))
      end
    end

    context 'when a specific weekday is closed_all_day' do
      before do
        inbox.update!(working_hours_enabled: true)
        inbox.working_hours.find_by(day_of_week: 1).update!(closed_all_day: true) # close Monday
      end

      it 'skips the closed day and lands on the next open one' do
        from = Time.zone.parse('2026-07-11 15:00 UTC') # Saturday
        # Monday is now closed, so the next opening is Tuesday 09:00.
        expect(described_class.next_opening(inbox, from: from)).to eq(Time.zone.parse('2026-07-14 09:00 UTC'))
      end
    end

    context 'with a non-UTC inbox timezone' do
      before { inbox.update!(timezone: 'America/Sao_Paulo', working_hours_enabled: true) }

      it 'computes the opening in the inbox timezone (09:00 BRT = 12:00 UTC)' do
        from = Time.zone.parse('2026-07-11 15:00 UTC') # Saturday
        expect(described_class.next_opening(inbox, from: from))
          .to eq(ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-07-13 09:00'))
      end
    end

    context 'when the inbox is nil (defensive)' do
      it 'returns the original instant' do
        from = Time.zone.parse('2026-07-11 15:00 UTC')
        expect(described_class.next_opening(nil, from: from)).to eq(from)
      end
    end
  end
end
