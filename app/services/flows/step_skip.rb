# frozen_string_literal: true

# Raised by an action to abort ITSELF with a readable reason that is NOT a failure: a guard
# fired (the inbox isn't WhatsApp Cloud, the template isn't approved, …) so the node did
# nothing on purpose. Flows::ActionService#execute catches it BEFORE the generic error
# rescue — so it never reaches ChatwootExceptionTracker (no Sentry noise) — and the
# Flows::RunnerService records the step as `skipped`, carrying this `code` into error_code.
class Flows::StepSkip < StandardError
  attr_reader :code

  def initialize(code, message = nil)
    @code = code.to_s
    super(message || @code)
  end
end
