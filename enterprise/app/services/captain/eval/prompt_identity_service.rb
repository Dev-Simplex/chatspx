# A identidade da versão do prompt que está valendo AGORA (bloco 6.02).
#
# `captain_assistants` não versiona prompt: ele é editado no lugar. Sem inventar um
# sistema de versões (que seria outro bloco), a identidade é uma IMPRESSÃO DIGITAL do
# que compõe o prompt. Duas execuções com o mesmo fingerprint rodaram o mesmo prompt;
# fingerprints diferentes = houve mudança entre elas, e a comparação tem sentido.
class Captain::Eval::PromptIdentityService
  def initialize(assistant:)
    @assistant = assistant
  end

  def fingerprint
    Digest::SHA256.hexdigest(snapshot.to_json)[0, 16]
  end

  # O que entra no fingerprint fica LEGÍVEL no snapshot: quem compara duas execuções
  # precisa ver o que mudou, não só que mudou.
  def snapshot
    {
      'name' => @assistant.name,
      'description' => @assistant.description,
      'response_guidelines' => Array(@assistant.response_guidelines),
      'guardrails' => Array(@assistant.guardrails),
      'config' => @assistant.config.presence || {},
      'scenarios' => scenarios
    }
  end

  private

  def scenarios
    @assistant.scenarios.order(:id).map do |scenario|
      {
        'id' => scenario.id,
        'title' => scenario.title,
        'instruction' => scenario.instruction,
        'tools' => Array(scenario.tools),
        'enabled' => scenario.enabled
      }
    end
  end
end
