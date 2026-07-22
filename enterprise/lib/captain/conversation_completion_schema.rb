class Captain::ConversationCompletionSchema < RubyLLM::Schema
  boolean :complete, description: 'Whether the conversation is complete and can be safely closed'
  string :classe, enum: %w[trivial substantive],
                  description: 'How disposable the conversation is, independent of completeness. ' \
                               'trivial = no real customer value at stake: a greeting that led nowhere, a wrong-business or ' \
                               'wrong-city mix-up, or a single simple factual question already answered in a self-contained way. ' \
                               'A trivial conversation is safe to close automatically. ' \
                               'substantive = real engagement worth preserving: the customer qualified, showed genuine interest, ' \
                               'negotiated, or raised any question of value — whether or not it was fully answered. ' \
                               'A substantive conversation must NOT be closed automatically; a human should review it first. ' \
                               'When unsure, answer substantive.'
  string :reason, description: 'Brief explanation of why the conversation is complete or incomplete'
end
