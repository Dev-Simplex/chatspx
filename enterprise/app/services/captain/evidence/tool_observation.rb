module Captain::Evidence::ToolObservation
  def perform(tool_context, **kwargs)
    scope = Captain::Evidence::Context.scope
    return super unless scope

    previous_publication = scope.publication_id

    return Captain::Evidence::Context.set(scope: nil) { super } unless evidence_tenant_matches?(scope)

    scope.publication_id = SecureRandom.uuid

    # Custom metadata is instance-bound. Never resolve a global slug constant to identify a tenant's tool.
    name = evidence_tool_name
    Captain::Evidence::Context.with_path("tool:#{name}") do
      result = super
      Captain::Evidence::Sources.record(origin: 'tool_return', name: name, version: '1', status: 'unverified',
                                        result: { output: result })
      result
    end
  rescue StandardError => e
    Captain::Evidence::Sources.record(origin: 'tool_return', name: name || 'unknown', version: '1', status: 'error',
                                      result: { error_class: e.class.name })
    raise
  ensure
    scope.publication_id = previous_publication if scope
  end

  private

  def evidence_tool_name
    @custom_tool ? "custom:#{@custom_tool.id}:#{@custom_tool.slug}" : self.class.name.demodulize.underscore
  end

  def evidence_tenant_matches?(scope)
    matches = @assistant.account_id == scope.account_id && (!@custom_tool || @custom_tool.account_id == scope.account_id)
    Captain::Evidence::Telemetry.emit(**scope.metadata, decision: 'unassessed', reason: 'tool_tenant_mismatch') unless matches
    matches
  end
end
