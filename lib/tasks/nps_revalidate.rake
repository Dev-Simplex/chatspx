# frozen_string_literal: true

# Rake task to retroactively flag NPS responses that were likely false positives.
#
# The old ScoreValidator had a catch-all /(\d+)/ regex that captured any number 0-10
# from ANY message as an NPS score (e.g., "tenho 5 filhos" → score 5).
#
# This task re-runs the FIXED validator against the original message content.
# If the fixed validator wouldn't have extracted the score, the response is flagged.
#
# Usage:
#   bundle exec rake nps:revalidate              # Dry run (default) — shows report, changes nothing
#   bundle exec rake nps:revalidate MODE=apply   # Flags suspect responses in the database
#   bundle exec rake nps:revalidate MODE=report  # Generates CSV report to tmp/nps_revalidation.csv
#
namespace :nps do # rubocop:disable Metrics/BlockLength
  desc 'Revalidate historical NPS responses and flag likely false positives'
  task revalidate: :environment do # rubocop:disable Metrics/BlockLength
    mode = ENV.fetch('MODE', 'dry_run')
    unless %w[dry_run apply report].include?(mode)
      puts "ERROR: MODE must be 'dry_run', 'apply', or 'report'. Got: '#{mode}'"
      exit 1
    end

    puts "=== NPS Revalidation (mode: #{mode}) ==="
    puts ''

    stats = { total: 0, ok: 0, suspect: 0, mismatch: 0, no_message: 0, widget: 0, already_flagged: 0 }
    csv_rows = []

    NpsResponse.where(status: :responded).find_each do |nps|
      stats[:total] += 1

      # Skip already flagged
      if nps.data_quality_flag.present?
        stats[:already_flagged] += 1
        next
      end

      nps_msg_id = nps.metadata&.dig('message_id')
      unless nps_msg_id
        stats[:no_message] += 1
        next
      end

      # Find the customer's RESPONSE — first incoming message after the NPS survey question
      response_message = Message.where(conversation_id: nps.conversation_id, message_type: :incoming)
                                .where('id > ?', nps_msg_id)
                                .order(:id)
                                .first
      unless response_message
        stats[:no_message] += 1
        next
      end

      # Widget submissions (buttons) are always legit — score came from structured input
      widget_score = response_message.content_attributes&.dig('submitted_values', 'nps_response', 'score')
      if widget_score.present?
        stats[:widget] += 1
        stats[:ok] += 1
        next
      end

      message = response_message
      # Re-run the FIXED ScoreValidator against the customer's response
      revalidated = NpsSurveys::ScoreValidator.validate_and_extract(message.content)

      if revalidated == nps.score
        stats[:ok] += 1
        next
      end

      # Flag it
      flag = revalidated.nil? ? 'suspect_false_positive' : 'score_mismatch'
      reason = if revalidated.nil?
                 "validator_returned_nil_for: #{message.content&.truncate(80)}"
               else
                 "score_was_#{nps.score}_validator_says_#{revalidated}"
               end

      if flag == 'suspect_false_positive'
        stats[:suspect] += 1
      else
        stats[:mismatch] += 1
      end

      csv_rows << {
        nps_id: nps.id,
        conversation_id: nps.conversation_id,
        contact_id: nps.contact_id,
        original_score: nps.score,
        revalidated_score: revalidated,
        flag: flag,
        message_content: message.content&.truncate(100),
        answered_at: nps.answered_at
      }

      if mode == 'dry_run'
        puts "  [#{flag.upcase}] NPS ##{nps.id} score=#{nps.score} → " \
             "validator=#{revalidated.inspect} content=\"#{message.content&.truncate(60)}\""
      end

      next unless mode == 'apply'

      nps.update_columns( # rubocop:disable Rails/SkipsModelValidations
        data_quality_flag: flag,
        flag_reason: reason,
        flagged_at: Time.current
      )
    end

    # Report
    puts ''
    puts '=== Results ==='
    puts "  Total responded:    #{stats[:total]}"
    puts "  Already flagged:    #{stats[:already_flagged]}"
    puts "  OK (legit):         #{stats[:ok]}"
    puts "    - Widget (button): #{stats[:widget]}"
    puts "  Suspect false pos:  #{stats[:suspect]}"
    puts "  Score mismatch:     #{stats[:mismatch]}"
    puts "  No message found:   #{stats[:no_message]}"
    puts ''

    if (stats[:suspect] + stats[:mismatch]).positive?
      pct = ((stats[:suspect] + stats[:mismatch]).to_f / (stats[:total] - stats[:already_flagged]) * 100).round(1)
      puts "  Impact: #{pct}% of responses are suspect"
    else
      puts '  No suspect responses found!'
    end

    case mode
    when 'dry_run'
      puts ''
      puts '  This was a DRY RUN — nothing was changed.'
      puts '  Run with MODE=apply to flag suspect responses.'
      puts '  Run with MODE=report to generate CSV.'
    when 'apply'
      puts ''
      puts "  #{stats[:suspect] + stats[:mismatch]} responses flagged in database."
    when 'report'
      if csv_rows.any?
        require 'csv'
        path = Rails.root.join('tmp/nps_revalidation.csv')
        CSV.open(path, 'w') do |csv|
          csv << csv_rows.first.keys
          csv_rows.each { |row| csv << row.values }
        end
        puts ''
        puts "  CSV report saved to: #{path}"
      end
    end
  end
end
