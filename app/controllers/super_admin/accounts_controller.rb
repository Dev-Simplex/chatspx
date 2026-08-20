class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  CAPTAIN_V2_FLAG = :feature_captain_integration_v2
  LEGACY_CAPTAIN_FLAG = :feature_captain_integration

  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact

    if params[:enabled_features].present?
      selected_feature_flags = enabled_feature_flags_from_params(params[:enabled_features])
      permitted_params[:selected_feature_flags] = synchronized_captain_feature_flags(selected_feature_flags)
    end

    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource.id)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account.class.name, account.id) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  def enabled_feature_flags_from_params(enabled_features)
    features_hash = enabled_features.respond_to?(:to_unsafe_h) ? enabled_features.to_unsafe_h : enabled_features.to_h

    features_hash.each_with_object([]) do |(flag, value), selected_flags|
      selected_flags << flag.to_sym if ActiveModel::Type::Boolean.new.cast(value)
    end
  end

  def synchronized_captain_feature_flags(selected_feature_flags)
    feature_flags = selected_feature_flags.dup

    if feature_flags.include?(CAPTAIN_V2_FLAG)
      feature_flags << LEGACY_CAPTAIN_FLAG
    else
      feature_flags.delete(LEGACY_CAPTAIN_FLAG)
    end

    feature_flags.uniq
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
