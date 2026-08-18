class AsyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    EventDispatcherJob.perform_later(event_name, timestamp, data)
  end

  def publish_event(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    [
      AutomationRuleListener.instance,
      Spx::Tozi::FunnelAutomationListener.instance,
      MessageSequences::ExitListener.instance,
      CampaignListener.instance,
      CsatSurveyListener.instance,
      NpsSurveyListener.instance,
      HookListener.instance,
      InstallationWebhookListener.instance,
      NotificationListener.instance,
      ParticipationListener.instance,
      Conversations::UnreadCounts::Listener.instance,
      ReportingEventListener.instance,
      # Bloco 5.03: registro server-side de eventos de tracking. Async de proposito — no
      # SyncDispatcher o mesmo fato seria registrado duas vezes.
      TrackingEventListener.instance,
      WebhookListener.instance
    ]
  end
end

AsyncDispatcher.prepend_mod_with('AsyncDispatcher')
