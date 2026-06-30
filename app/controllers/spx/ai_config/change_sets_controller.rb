# Endpoints de escrita/auditoria do receptor + endpoints de test-gate consumidos
# pelo Almirante ANTES de aplicar (test_credential / perform_test / eval_prompt).
module Spx
  module AiConfig
    class ChangeSetsController < BaseController
      # POST /spx/ai_config/change_sets/dry_run — preview/diff, sem escrita.
      def dry_run
        applier = ChangeSetApplier.new(change_set_params)
        render json: { change_set_id: change_set_params['change_set_id'], diff: applier.dry_run }
      end

      # POST /spx/ai_config/change_sets — aplica (transacional/idempotente/auditado).
      def apply
        applier = ChangeSetApplier.new(change_set_params)
        record = applier.apply!
        render json: serialize_change(record), status: :ok
      end

      # POST /spx/ai_config/change_sets/:change_set_id/revert — restaura o snapshot.
      def revert
        record = ChangeSetApplier.revert!(params[:change_set_id])
        render json: serialize_change(record), status: :ok
      end

      # GET /spx/ai_config/change_sets/:change_set_id — auditoria de um change-set.
      def show
        record = AiConfigChange.find_by!(change_set_id: params[:change_set_id])
        render json: serialize_change(record)
      end

      # --- TEST-GATE (consumido pelo Almirante; NAO persiste config) ---

      # POST /spx/ai_config/test_credential — testa as `settings` propostas contra o
      # provider real (Vista/Google), SEM salvar. Merge sobre o armazenado pulando
      # secrets mascarados, igual ao apply.
      def test_credential
        provider = params[:provider].to_s
        return render json: { ok: false, error: 'unsupported_provider' } unless AccountIntegration::SUPPORTED_PROVIDERS.include?(provider)

        proposed = proposed_credential_settings(provider)
        result = case provider
                 when 'vista' then test_vista_connection(proposed)
                 when 'google' then test_google_connection(proposed)
                 end
        render json: result
      end

      # POST /spx/ai_config/perform_test — dispara a tool DE VERDADE contra um payload
      # sintetico (test-gate F4). Custom tool: HTTP request real ao endpoint via
      # Captain::Tools::HttpTool#perform_test (mesma SSRF guard/auth do #perform).
      # Built-in: dry-call segura (perform real, mas em txn revertida pra neutralizar
      # qualquer escrita no banco). Retorna {ok, status, body}.
      def perform_test
        assistant = Captain::Assistant.find_by!(id: params[:assistant_id], account_id: params[:account_id])
        tool_id = params[:tool_id].to_s
        available = assistant.available_tool_ids
        return render json: { ok: false, error: 'tool_id_unavailable', available_tool_ids: available } unless available.include?(tool_id)

        custom = assistant.account.captain_custom_tools.enabled.find_by(slug: tool_id)
        result = if custom
                   perform_custom_tool_test(assistant, custom)
                 else
                   perform_built_in_tool_test(assistant, tool_id)
                 end
        render json: { tool_id: tool_id, kind: custom ? 'custom' : 'built_in' }.merge(result)
      end

      # Cap default de cenarios executados por chamada de eval (evita rodada custosa de
      # LLM contra dezenas de cenarios). Override por request com `max_scenarios`.
      DEFAULT_EVAL_SCENARIO_CAP = 8

      # POST /spx/ai_config/eval_prompt — roda o agente DE VERDADE (engine Captain) contra
      # os captain_scenarios da conta com o prompt candidato (override de config['instructions']
      # EM MEMORIA, sem salvar). Retorna por cenario {scenario_id, response, tool_calls}.
      # Cap de cenarios (DEFAULT_EVAL_SCENARIO_CAP / `max_scenarios`) limita custo. Passe
      # `execute=false` pra um dry-run estrutural (sem LLM) quando so quiser listar cenarios.
      def eval_prompt
        assistant = Captain::Assistant.find_by!(id: params[:assistant_id], account_id: params[:account_id])
        candidate = params[:instructions].presence || assistant.config['instructions']
        execute = params[:execute].nil? || ActiveModel::Type::Boolean.new.cast(params[:execute])

        all_scenarios = eval_scenarios(assistant)
        scenarios = all_scenarios.first(eval_scenario_cap)
        results = scenarios.map { |scenario| eval_scenario(assistant, candidate, scenario, execute) }

        render json: {
          assistant_id: assistant.id,
          candidate_instructions_present: params[:instructions].present?,
          executed: execute == true,
          scenario_count: scenarios.length,
          total_scenarios: all_scenarios.length,
          capped: all_scenarios.length > scenarios.length,
          results: results
        }
      end

      private

      def change_set_params
        # Caller e maquina-confiavel atras de token admin; o applier so le chaves
        # conhecidas (validate_shape! + deep_stringify_keys), mass-assignment contido.
        params.require(:change_set).to_unsafe_h
      end

      def serialize_change(record)
        {
          id: record.id,
          change_set_id: record.change_set_id,
          account_id: record.account_id,
          assistant_id: record.assistant_id,
          status: record.status,
          author: record.author,
          approved_by: record.approved_by,
          operations: record.operations,
          snapshot_before: record.snapshot_before,
          result: record.result,
          error_message: record.error_message,
          applied_at: record.applied_at,
          reverted_at: record.reverted_at,
          created_at: record.created_at
        }
      end

      # ---- credencial ----

      def proposed_credential_settings(provider)
        account = Account.find(params[:account_id])
        stored = account.account_integrations.find_by(provider: provider)&.settings || {}
        submitted = (params[:settings] || {}).respond_to?(:to_unsafe_h) ? params[:settings].to_unsafe_h : (params[:settings] || {})
        merged = stored.dup
        submitted.to_h.each do |key, value|
          next if AccountIntegration::SECRET_KEYS.include?(key.to_s) && (value.blank? || value.to_s.include?('*'))

          merged[key.to_s] = value
        end
        merged
      end

      def test_vista_connection(settings)
        api_key = settings['vista_api_key']
        base_url = settings['vista_base_url']
        return { ok: false, error: 'missing_credentials' } if api_key.blank? || base_url.blank?

        pesquisa = { fields: ['Codigo'], paginacao: { pagina: 1, quantidade: 1 } }.to_json
        url = "#{base_url.to_s.chomp('/')}/imoveis/listar"
        response = connection_tester_http.get(url, { key: api_key, pesquisa: pesquisa, showtotal: 1 },
                                              { 'Accept' => 'application/json' })
        { ok: response.success?, status: response.status }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      # Ping REAL a Google (Places Text Search) espelhando o BuscarLugarTool — valida que a
      # chave AUTENTICA, nao so que existe. Query barata; 200 = chave boa, 4xx = auth/quota.
      def test_google_connection(settings)
        key = settings['google_maps_key']
        return { ok: false, error: 'missing_google_maps_key' } if key.blank?

        resp = HTTParty.post(
          'https://places.googleapis.com/v1/places:searchText',
          headers: {
            'Content-Type' => 'application/json',
            'X-Goog-Api-Key' => key,
            'X-Goog-FieldMask' => 'places.displayName'
          },
          body: { textQuery: 'Sinop MT', languageCode: 'pt-BR', regionCode: 'BR' }.to_json,
          timeout: 15
        )
        { ok: resp.code == 200, status: resp.code }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def connection_tester_http
        Faraday.new do |faraday|
          faraday.options.open_timeout = 5
          faraday.options.timeout = 10
          faraday.adapter Faraday.default_adapter
        end
      end

      # ---- perform_test (tool de verdade) ----

      # Custom tool: HTTP request real ao endpoint via HttpTool#perform_test (mesma SSRF
      # guard/auth do #perform). Payload sintetico derivado do param_schema (ou `tool_params`).
      def perform_custom_tool_test(assistant, custom)
        tool = custom.tool(assistant)
        synth = synthetic_params_from_schema(custom.param_schema, params[:tool_params])
        tool.perform_test(**synth)
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      # Built-in: dry-call seguro. Roda o #perform real (cobre tools read-only que pingam
      # API externa, ex. Vista/Google) mas dentro de uma txn SEMPRE revertida, neutralizando
      # qualquer escrita no banco. State sintetico minimo (sem conversa) — tools que dependem
      # de conversa retornam a propria mensagem de "sem contexto" sem mutar nada.
      def perform_built_in_tool_test(assistant, tool_id)
        tool_class = Captain::Assistant.resolve_tool_class(tool_id)
        return { ok: false, error: 'tool_class_unresolved' } if tool_class.nil?

        tool = tool_class.new(assistant)
        synth = synthetic_params_from_tool(tool, params[:tool_params])
        ctx = synthetic_tool_context(assistant)

        body = nil
        ActiveRecord::Base.transaction do
          body = tool.perform(ctx, **synth)
          raise ActiveRecord::Rollback
        end
        { ok: true, status: 200, body: body.to_s[0, 5000], dry_call: true }
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      def synthetic_params_from_schema(schema, provided)
        given = unsafe_hash(provided)
        Array(schema).each_with_object({}) do |param, acc|
          name = param['name'] || param[:name]
          next if name.blank?

          value = given[name.to_s]
          acc[name.to_sym] = value.nil? ? sample_for_type(param['type'] || param[:type]) : value
        end
      end

      def synthetic_params_from_tool(tool, provided)
        given = unsafe_hash(provided)
        tool.parameters.each_with_object({}) do |(name, param), acc|
          next unless param.required

          value = given[name.to_s]
          acc[name.to_sym] = value.nil? ? sample_for_type(param.type) : value
        end
      rescue StandardError
        {}
      end

      def sample_for_type(type)
        case type.to_s
        when 'number', 'integer' then 1
        when 'boolean' then true
        else 'test'
        end
      end

      def synthetic_tool_context(assistant)
        run_context = Agents::RunContext.new(
          { state: { account_id: assistant.account_id, assistant_id: assistant.id, assistant_config: assistant.config } }
        )
        Agents::ToolContext.new(run_context: run_context)
      end

      def unsafe_hash(value)
        return {} if value.blank?

        (value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value).to_h.stringify_keys
      end

      # ---- eval_prompt ----

      def eval_scenario_cap
        cap = params[:max_scenarios].to_i
        cap.positive? ? cap : DEFAULT_EVAL_SCENARIO_CAP
      end

      def eval_scenarios(assistant)
        scenario_ids = Array(params[:scenario_ids]).map(&:to_i).reject(&:zero?)
        scope = assistant.scenarios.enabled
        scope = scope.where(id: scenario_ids) if scenario_ids.any?
        scope.order(:id).to_a
      end

      def eval_scenario(assistant, candidate, scenario, execute)
        base = {
          scenario_id: scenario.id,
          title: scenario.title,
          instruction: scenario.instruction,
          expected_tools: scenario.tools,
          executed: false
        }
        return base.merge(todo: 'execucao do engine Captain desabilitada (execute=false)') unless execute

        run_candidate_scenario(assistant, candidate, scenario)
          .merge(scenario_id: scenario.id, title: scenario.title, expected_tools: scenario.tools, executed: true)
      rescue StandardError => e
        base.merge(error: e.message)
      end

      # Override do prompt EM MEMORIA (sem salvar) — o agente le config['instructions']
      # vivo via prompt_context, entao basta reatribuir o config do registro carregado.
      # run_raw devolve o RunResult cru pra extrair tool_calls/handoffs por mensagem.
      def run_candidate_scenario(assistant, candidate, scenario)
        candidate_assistant = assistant
        if candidate.present? && candidate != assistant.config['instructions']
          candidate_assistant = Captain::Assistant.find(assistant.id)
          candidate_assistant.config = candidate_assistant.config.merge('instructions' => candidate)
        end

        history = [{ role: 'user', content: scenario.instruction.to_s }]
        result = Captain::Assistant::AgentRunnerService
                 .new(assistant: candidate_assistant)
                 .run_raw(message_history: history)

        {
          response: eval_response_text(result),
          agent_name: result.try(:context)&.dig(:current_agent),
          tool_calls: eval_tool_calls(result)
        }
      end

      def eval_response_text(result)
        output = result.try(:output)
        return output['response'] || output[:response] || output.to_s if output.is_a?(Hash)

        output.to_s
      end

      # tool_calls de todas as mensagens de assistant do run (MessageExtractor expõe
      # :tool_calls como array de hashes id/name/arguments). So nome+args pro Almirante.
      def eval_tool_calls(result)
        Array(result.try(:messages)).flat_map do |msg|
          calls = msg[:tool_calls] || msg['tool_calls']
          next [] if calls.blank?

          Array(calls).map do |tc|
            tc = tc.respond_to?(:to_h) ? tc.to_h : tc
            { name: tc[:name] || tc['name'], arguments: tc[:arguments] || tc['arguments'] }
          end
        end
      end
    end
  end
end
