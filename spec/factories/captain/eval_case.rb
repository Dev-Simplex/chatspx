FactoryBot.define do
  factory :captain_eval_case, class: 'Captain::EvalCase' do
    sequence(:titulo) { |n| "Caso #{n}" }
    mensagens { [{ 'role' => 'user', 'content' => 'Tem casa de 3 quartos?' }] }
    expectativas { {} }
    association :account
    association :captain_assistant, factory: :captain_assistant

    before(:create) do |eval_case|
      eval_case.account ||= eval_case.captain_assistant.account
    end
  end
end
