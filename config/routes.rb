Rails.application.routes.draw do
  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    token_validations: 'devise_overrides/token_validations',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks'
  }, via: [:get, :post]

  ## renders the frontend paths only if its not an api only server
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false))
    root to: 'api#index'
  else
    root to: 'dashboard#index'

    get '/app', to: 'dashboard#index'
    get '/app/*params', to: 'dashboard#index'
    get '/app/accounts/:account_id/settings/inboxes/new/twitter', to: 'dashboard#index', as: 'app_new_twitter_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/microsoft', to: 'dashboard#index', as: 'app_new_microsoft_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/instagram', to: 'dashboard#index', as: 'app_new_instagram_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/tiktok', to: 'dashboard#index', as: 'app_new_tiktok_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_twitter_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_email_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_instagram_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_tiktok_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_instagram_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_tiktok_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_email_inbox_settings'

    resource :widget, only: [:show]
    namespace :survey do
      resources :responses, only: [:show]
    end
    resource :slack_uploads, only: [:show]
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ----------------------------------
      # start of account scoped api routes
      resources :accounts, only: [:create, :show, :update] do
        member do
          post :update_active_at
          get :cache_keys
          post :chat_wallpaper
          delete :chat_wallpaper
        end

        scope module: :accounts do
          namespace :actions do
            resource :contact_merge, only: [:create]
          end
          resource :bulk_actions, only: [:create]
          resources :agents, only: [:index, :create, :update, :destroy] do
            post :bulk_create, on: :collection
          end
          resource :agent_stats, only: [:show]
          # Alias do contrato C1 do briefing (sem o prefixo /captain). A rota
          # canonica e a de dentro do namespace :captain, onde o recurso vive;
          # este alias existe para quem implementou o cliente pelo caminho
          # literal do contrato.
          post 'copilot_threads/:copilot_thread_id/stream', to: 'captain/copilot_streams#create'
          delete 'copilot_threads/:copilot_thread_id/stream', to: 'captain/copilot_streams#destroy'
          namespace :captain do
            resource :preferences, only: [:show, :update]
            resources :assistants do
              member do
                post :playground
                get :stats
              end
              collection do
                get :tools
              end
              resources :inboxes, only: [:index, :create, :destroy], param: :inbox_id
              resources :scenarios
            end
            resources :assistant_logs, only: [:index]
            resources :assistant_responses
            resources :bulk_actions, only: [:create]
            resources :copilot_threads, only: [:index, :create] do
              resources :copilot_messages, only: [:index, :create]
              # Streaming SSE do copiloto (contrato C1).
              # POST   .../captain/copilot_threads/:copilot_thread_id/stream  -> gera
              # DELETE .../captain/copilot_threads/:copilot_thread_id/stream  -> "parar"
              resource :stream, only: [:create, :destroy], controller: 'copilot_streams'
            end
            resources :custom_tools do
              member do
                post :test
              end
            end
            resources :documents, only: [:index, :show, :create, :destroy]
            resource :tasks, only: [], controller: 'tasks' do
              post :rewrite
              post :summarize
              post :reply_suggestion
              post :label_suggestion
              post :follow_up
              post :sentiment_analysis
            end
          end
          resource :saml_settings, only: [:show, :create, :update, :destroy]
          resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
            delete :avatar, on: :member
            post :reset_access_token, on: :member
          end
          resources :contact_inboxes, only: [] do
            collection do
              post :filter
            end
          end
          resources :assignable_agents, only: [:index]
          resource :audit_logs, only: [:show]
          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end
          resources :canned_responses, only: [:index, :create, :update, :destroy]
          resources :automation_rules, only: [:index, :create, :show, :update, :destroy] do
            post :clone
          end
          resources :macros, only: [:index, :create, :show, :update, :destroy] do
            post :execute, on: :member
          end
          resources :flows, only: [:index, :create, :show, :update, :destroy] do
            member do
              post :execute
              post :simulate
              get :logs
              get :stats
            end
            post :import, on: :collection
          end
          resources :sla_policies, only: [:index, :create, :show, :update, :destroy]
          resources :custom_roles, only: [:index, :create, :show, :update, :destroy]
          resources :agent_capacity_policies, only: [:index, :create, :show, :update, :destroy] do
            scope module: :agent_capacity_policies do
              resources :users, only: [:index, :create, :destroy]
              resources :inbox_limits, only: [:create, :update, :destroy]
            end
          end
          resources :campaigns, only: [:index, :create, :show, :update, :destroy] do
            member do
              get :stats
              post :recipients
              post :start
              post :pause
            end
          end
          resources :funnels, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :templates
              post :create_from_template
            end
            member do
              post :reorder_stages
              get :stats
              post :form
            end
            resources :funnel_stages, only: [:index, :show, :create, :update, :destroy]
            resources :custom_fields, only: [:index, :show, :create, :update, :destroy], module: :funnels
            resources :automations, only: [:index, :show, :create, :update, :destroy], module: :funnels
            resources :funnel_items, only: [:index, :create, :update, :destroy] do
              member do
                patch :custom_attributes
              end
              collection do
                post :bulk_move
                post :bulk_update
                post :reorder
              end
              resources :funnel_item_notes, only: [:index, :create, :destroy], path: 'notes', module: :funnels
            end
          end
          resources :funnel_views, only: [:index, :show, :create, :update, :destroy]
          get 'kanban_ai/status', to: 'kanban_ai#status'
          resources :scheduled_messages, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :inboxes
            end
          end
          resources :message_sequences, only: [:index, :show, :create, :update, :destroy]
          resources :message_sequence_enrollments, only: [:index, :create, :destroy]
          resources :internal_channels, only: [:index, :show, :create, :update] do
            collection do
              get :mentions
              get :search
            end
            member do
              post :read
              post :typing
              post :add_member
              delete :remove_member
              post :leave
            end
            resources :internal_messages, only: [:index, :create, :update, :destroy], module: :internal_channels do
              member { post :react }
            end
          end
          resources :agents_for_internal_chat, only: [:index], controller: :internal_chat_agents
          resources :dashboard_apps, only: [:index, :show, :create, :update, :destroy]
          namespace :channels do
            resource :twilio_channel, only: [:create]
          end
          resources :conversations, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :meta
              get :search
              post :filter
            end
            scope module: :conversations do
              # D1 (Fase 3): pedir o atendimento de uma conversa de outro agente.
              # Pendurado aqui p/ herdar `authorize :show?` + authorize_team_access
              # do Conversations::BaseController de graça.
              resources :takeover_requests, only: [:create]
              resources :messages, only: [:index, :create, :destroy, :update] do
                member do
                  post :translate
                  post :retry
                  # PR G1 — coletivo pin (cap 3) em conversations.additional_attributes.pinned_message_ids
                  post :pin, to: 'messages/pin#create'
                  delete :pin, to: 'messages/pin#destroy'
                end
                collection do
                  post :share_location
                  post :share_contact
                end
                scope module: :messages do
                  # PR B1 — persisted reactions (index/create/destroy). Plural `resources`
                  # so each reaction has its own id for destroy.
                  resources :reactions, only: [:index, :create, :destroy]
                  resource :star, only: [:create, :destroy]
                end
              end
              resources :assignments, only: [:create]
              resources :funnel_items, only: [:index]
              resources :labels, only: [:create, :index]
              resource :participants, only: [:show, :create, :update, :destroy]
              # I3 — integrantes do grupo de WhatsApp (WAHA). show le o snapshot
              # gravado; create e o "Sincronizar agora" do painel.
              resource :waha_group, only: [:show, :create], controller: 'waha_group'
              resource :direct_uploads, only: [:create]
              resource :draft_messages, only: [:show, :update, :destroy]
              resource :ghost_suggestion, only: [:create]
              resource :copilot_chat, only: [:create, :show, :destroy]
              # PR B4 — per-user jsonb settings (pinned, archived_at, muted_until, theme_key)
              resource :user_setting, only: [:update, :destroy], controller: 'user_settings'
            end
            member do
              post :mute
              post :unmute
              post :transcript
              post :toggle_status
              post :toggle_priority
              post :retriage
              post :toggle_typing_status
              post :update_last_seen
              post :unread
              post :custom_attributes
              get :attachments
              get :inbox_assistant
              get :reporting_events if ChatwootApp.enterprise?
              get 'nps_response', to: 'nps_responses#show_by_conversation'
              post 'nps_responses/send', to: 'nps_responses#send_survey'
            end
          end

          namespace :private_chat do
            post 'unlock', to: 'unlock#create'
            post 'clear', to: 'messages#clear'
            resources :messages, only: [:index, :create]
          end

          resources :search, only: [:index] do
            collection do
              get :conversations
              get :messages
              get :contacts
              get :articles
            end
          end

          resources :attachments, only: [:index] do
            collection do
              get :links
            end
          end

          resources :attachment_bulk_downloads, only: [:create, :show]

          resources :companies, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :search
            end
          end
          # Aba "Em atendimento": metadado de quem está sendo atendido por quem
          # (conversa-shaped, por isso fora do contacts_controller).
          resources :active_attendances, only: [:index]
          # D1 (Fase 3): responder/acompanhar pedidos. Nível de CONTA (não de
          # conversa) porque o dono responde a partir de uma lista, não de dentro
          # da conversa. O index filtra por owner_id/requester_id → seguro por
          # construção, sem precisar de PermissionFilterService.
          resources :takeover_requests, only: [:index] do
            member do
              post :approve
              post :deny
              post :cancel
            end
          end
          resources :contacts, only: [:index, :show, :update, :create, :destroy] do
            collection do
              get :active
              get :search
              get :search_for_schedule
              post :filter
              post :import
              post :export
            end
            member do
              get :contactable_inboxes
              post :destroy_custom_attributes
              post :revalidate_whatsapp
              delete :avatar
            end
            scope module: :contacts do
              resources :conversations, only: [:index]
              resources :contact_inboxes, only: [:create]
              resources :labels, only: [:create, :index]
              resources :notes

              post :call, on: :member, to: 'calls#create' if ChatwootApp.enterprise?
            end
          end

          resources :messages, only: [] do
            member do
              post :forward, to: 'messages/forward#create'
            end
          end

          resources :messages, only: [] do
            member do
              post :forward, to: 'messages/forward#create'
            end
          end
          resources :csat_survey_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if ChatwootApp.enterprise?
            end
          end
          resources :nps_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if ChatwootApp.enterprise?
            end
          end
          resources :nps_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :applied_slas, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :report_pdf_exports, only: %i[create show]
          resources :reporting_events, only: [:index] if ChatwootApp.enterprise?
          resources :custom_attribute_definitions, only: [:index, :show, :create, :update, :destroy]
          resources :custom_filters, only: [:index, :show, :create, :update, :destroy]
          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            post :register_webhook, on: :member
            if ChatwootApp.enterprise?
              resource :conference, only: %i[create destroy], controller: 'conference' do
                get :token, on: :member
              end
            end

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates' do
              post :analyze, on: :collection
            end

            resources :message_templates, only: [:index, :create, :destroy], controller: 'inbox_message_templates'
          end
          resources :waha_connections, only: [:index, :show, :create, :destroy] do
            member do
              get :qr_code
              post :connect
              post :disconnect
              post :restart
            end
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :labels, only: [:index, :show, :create, :update, :destroy]

          resources :notifications, only: [:index, :update, :destroy] do
            collection do
              post :read_all
              get :unread_count
              post :destroy_all
            end
            member do
              post :snooze
              post :unread
            end
          end
          resource :notification_settings, only: [:show, :update]

          resources :teams do
            resources :team_members, only: [:index, :create] do
              collection do
                delete :destroy
                patch :update
              end
            end
          end

          # Assignment V2 Routes
          resources :assignment_policies do
            resources :inboxes, only: [:index, :create, :destroy], module: :assignment_policies
          end

          resources :inboxes, only: [] do
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
          end

          namespace :notion do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
          end

          resources :webhooks, only: [:index, :create, :update, :destroy]
          namespace :integrations do
            resources :apps, only: [:index, :show]
            resources :hooks, only: [:show, :create, :update, :destroy] do
              member do
                post :process_event
              end
            end
            resource :slack, only: [:create, :update, :destroy], controller: 'slack' do
              member do
                get :list_all_channels
              end
            end
            resource :dyte, controller: 'dyte', only: [] do
              collection do
                post :create_a_meeting
                post :add_participant_to_meeting
              end
            end
            resource :shopify, controller: 'shopify', only: [:destroy] do
              collection do
                post :auth
                get :orders
              end
            end
            resource :linear, controller: 'linear', only: [] do
              collection do
                delete :destroy
                get :teams
                get :team_entities
                post :create_issue
                post :link_issue
                post :unlink_issue
                get :search_issue
                get :linked_issues
              end
            end
            resource :notion, controller: 'notion', only: [] do
              collection do
                delete :destroy
              end
            end
            resource :openai, controller: 'openai', only: [] do
              collection do
                post :test_key
              end
            end
          end

          # Account-level provider integrations (Vista / Google) — editable, masked credentials.
          # Declared AFTER `namespace :integrations` so its nested routes (apps/hooks/slack/...)
          # keep route precedence; :id here is the provider slug (vista|google).
          resources :integrations, only: [:index, :show, :update] do
            member do
              post :test_connection
            end
          end
          resources :working_hours, only: [:update]

          resources :portals do
            member do
              patch :archive
              delete :logo
              post :send_instructions
              get :ssl_status
            end
            resources :categories do
              post :reorder, on: :collection
            end
            resources :articles do
              post :reorder, on: :collection
            end
          end

          resources :upload, only: [:create]
        end
      end
      # end of account scoped api routes
      # ----------------------------------

      namespace :integrations do
        resources :webhooks, only: [:create]
      end

      # Frontend API endpoint to trigger SAML authentication flow
      post 'auth/saml_login', to: 'auth#saml_login'

      resource :profile, only: [:show, :update] do
        delete :avatar, on: :collection
        member do
          post :availability
          post :auto_offline
          put :set_active_account
          post :resend_confirmation
          post :reset_access_token
          patch :ui_settings, action: :update_ui_settings
        end

        # MFA routes
        scope module: 'profile' do
          resource :mfa, controller: 'mfa', only: [:show, :create, :destroy] do
            post :verify
            post :backup_codes
          end
        end
      end

      resource :notification_subscriptions, only: [:create, :destroy]

      namespace :widget do
        resource :direct_uploads, only: [:create]
        resource :config, only: [:create]
        resources :campaigns, only: [:index]
        resources :events, only: [:create]
        resources :messages, only: [:index, :create, :update]
        resources :conversations, only: [:index, :create] do
          collection do
            post :destroy_custom_attributes
            post :set_custom_attributes
            post :update_last_seen
            post :toggle_typing
            post :transcript
            get  :toggle_status
          end
        end
        resource :contact, only: [:show, :update] do
          collection do
            post :destroy_custom_attributes
            patch :set_user
          end
        end
        resources :inbox_members, only: [:index]
        resources :labels, only: [:create, :destroy]
        namespace :integrations do
          resource :dyte, controller: 'dyte', only: [] do
            collection do
              post :add_participant_to_meeting
            end
          end
        end
      end
    end

    namespace :v2 do
      resources :accounts, only: [:create] do
        scope module: :accounts do
          resources :summary_reports, only: [] do
            collection do
              get :agent
              get :agent_assignment
              get :team
              get :inbox
              get :label
              get :channel
            end
          end
          resources :reports, only: [:index] do
            collection do
              get :summary
              get :bot_summary
              get :agents
              get :inboxes
              get :labels
              get :teams
              get :conversations
              get :conversations_summary
              get :conversation_traffic
              get :bot_metrics
              get :inbox_label_matrix
              get :first_response_time_distribution
              get :outgoing_messages_count
            end
          end
          resource :year_in_review, only: [:show]
          resources :live_reports, only: [] do
            collection do
              get :conversation_metrics
              get :grouped_conversation_metrics
              get :in_service_overview
              get :in_service_conversations
            end
          end

          resources :conversations, only: [] do
            resources :pdf_exports, only: %i[create show], controller: 'conversations/pdf_exports'
          end
        end
      end
    end
  end

  if ChatwootApp.enterprise?
    namespace :enterprise, defaults: { format: 'json' } do
      namespace :api do
        namespace :v1 do
          resources :accounts do
            member do
              post :checkout
              post :subscription
              get :limits
              post :toggle_deletion
              post :topup_checkout
            end
          end
        end
      end

      post 'webhooks/stripe', to: 'webhooks/stripe#process_payload'
      post 'webhooks/firecrawl', to: 'webhooks/firecrawl#process_payload'
    end
  end

  # ----------------------------------------------------------------------
  # Routes for platform APIs
  namespace :platform, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :users, only: [:create, :show, :update, :destroy] do
          member do
            get :login
            post :token
          end
        end
        resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
          delete :avatar, on: :member
        end
        resources :accounts, only: [:index, :create, :show, :update, :destroy] do
          resources :account_users, only: [:index, :create] do
            collection do
              delete :destroy
            end
          end
          resources :email_channel_migrations, only: [:create]
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Routes for inbox APIs Exposed to contacts
  namespace :public, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :inboxes do
          scope module: :inboxes do
            resources :contacts, only: [:create, :show, :update] do
              resources :conversations, only: [:index, :create, :show] do
                member do
                  post :toggle_status
                  post :toggle_typing
                  post :update_last_seen
                end

                resources :messages, only: [:index, :create, :update]
              end
            end
          end
        end

        resources :csat_survey, only: [:show, :update]

        # Kanban v2 (Fase 8): public WorkForm intake (token-identified, rate-limited)
        get 'funnel_forms/:token', to: 'funnel_forms#show'
        post 'funnel_forms/:token', to: 'funnel_forms#create'
      end
    end
  end

  get 'hc/:slug', to: 'public/api/v1/portals#show'
  get 'hc/:slug/sitemap.xml', to: 'public/api/v1/portals#sitemap'
  get 'hc/:slug/:locale', to: 'public/api/v1/portals#show'
  get 'hc/:slug/:locale/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/:locale/categories', to: 'public/api/v1/portals/categories#index'
  get 'hc/:slug/:locale/categories/:category_slug', to: 'public/api/v1/portals/categories#show'
  get 'hc/:slug/:locale/categories/:category_slug/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/articles/:article_slug.png', to: 'public/api/v1/portals/articles#tracking_pixel'
  get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show'

  # ----------------------------------------------------------------------
  # Used in mailer templates
  resource :app, only: [:index] do
    resources :accounts do
      resources :conversations, only: [:show]
    end
  end

  # ----------------------------------------------------------------------
  # Routes for channel integrations
  mount Facebook::Messenger::Server, at: 'bot'
  get 'webhooks/twitter', to: 'api/v1/webhooks#twitter_crc'
  post 'webhooks/twitter', to: 'api/v1/webhooks#twitter_events'
  post 'webhooks/line/:line_channel_id', to: 'webhooks/line#process_payload'
  post 'webhooks/telegram/:bot_token', to: 'webhooks/telegram#process_payload'
  post 'webhooks/waha/:session_name', to: 'webhooks/waha#process_payload'
  post 'webhooks/sms/:phone_number', to: 'webhooks/sms#process_payload'
  get 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'
  get 'webhooks/instagram', to: 'webhooks/instagram#verify'
  post 'webhooks/instagram', to: 'webhooks/instagram#events'
  post 'webhooks/tiktok', to: 'webhooks/tiktok#events'
  post 'webhooks/shopify', to: 'webhooks/shopify#events'
  get 'webhooks/meta_lead_ads', to: 'webhooks/meta_lead_ads#verify'
  post 'webhooks/meta_lead_ads', to: 'webhooks/meta_lead_ads#process_payload'
  # F1 (R-2): gatilho `external_webhook` do motor Flow — endpoint PÚBLICO identificado por token
  # forte (não pelo id). Rate-limitado por IP no rack_attack.rb. Ver Webhooks::FlowsController.
  post 'webhooks/flows/:token', to: 'webhooks/flows#create'

  namespace :twitter do
    resource :callback, only: [:show]
  end

  namespace :linear do
    resource :callback, only: [:show]
  end

  namespace :shopify do
    resource :callback, only: [:show]
  end

  namespace :twilio do
    resources :callback, only: [:create]
    resources :delivery_status, only: [:create]

    if ChatwootApp.enterprise?
      post 'voice/call/:phone', to: 'voice#call_twiml', as: :voice_call
      post 'voice/status/:phone', to: 'voice#status', as: :voice_status
      post 'voice/conference_status/:phone', to: 'voice#conference_status', as: :voice_conference_status
    end
  end

  get 'microsoft/callback', to: 'microsoft/callbacks#show'
  get 'google/callback', to: 'google/callbacks#show'
  get 'instagram/callback', to: 'instagram/callbacks#show'
  get 'tiktok/callback', to: 'tiktok/callbacks#show'
  get 'notion/callback', to: 'notion/callbacks#show'
  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/assetlinks.json' => 'android_app#assetlinks'
  get '.well-known/apple-app-site-association' => 'apple_app#site_association'
  get '.well-known/microsoft-identity-association.json' => 'microsoft#identity_association'
  get '.well-known/cf-custom-hostname-challenge/:id', to: 'custom_domains#verify'

  # ----------------------------------------------------------------------
  # Internal Monitoring Routes
  require 'sidekiq/web'
  require 'sidekiq/cron/web'

  devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }
  devise_scope :super_admin do
    get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'
    namespace :super_admin do
      root to: 'dashboard#index'

      resource :app_config, only: [:show, :create]

      # order of resources affect the order of sidebar navigation in super admin
      resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        post :seed, on: :member
        post :reset_cache, on: :member
      end
      resources :users, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :access_tokens, only: [:index, :show]
      resources :installation_configs, only: [:index, :new, :create, :show, :edit, :update]
      resources :agent_bots, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end
      resources :platform_apps, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resource :instance_status, only: [:show]

      resource :settings, only: [:show] do
        get :refresh, on: :collection
        post :force_refresh, on: :collection
      end

      # resources that doesn't appear in primary navigation in super admin
      resources :account_users, only: [:new, :create, :show, :destroy]
    end
    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  namespace :installation do
    get 'onboarding', to: 'onboarding#index'
    post 'onboarding', to: 'onboarding#create'
  end

  # Receptor de change-sets de IA (control plane Almirante). Auth maquina-a-maquina
  # via header api_access_token (owner PlatformApp) — ver Spx::AiConfig::BaseController.
  namespace :spx, defaults: { format: 'json' } do
    namespace :ai_config do
      get  'accounts/:account_id/assistants',                        to: 'config#assistants'
      get  'accounts/:account_id/assistants/:assistant_id/baseline', to: 'config#baseline'
      post 'change_sets/dry_run',               to: 'change_sets#dry_run'
      post 'change_sets',                       to: 'change_sets#apply'
      post 'change_sets/:change_set_id/revert', to: 'change_sets#revert'
      get  'change_sets/:change_set_id',        to: 'change_sets#show'
      post 'test_credential',                   to: 'change_sets#test_credential'
      post 'perform_test',                      to: 'change_sets#perform_test'
      post 'eval_prompt',                       to: 'change_sets#eval_prompt'
    end
  end

  # ---------------------------------------------------------------------
  # Routes for swagger docs
  get '/swagger/*path', to: 'swagger#respond'
  get '/swagger', to: 'swagger#respond'

  # ----------------------------------------------------------------------
  # Routes for testing
  resources :widget_tests, only: [:index] unless Rails.env.production?
end
