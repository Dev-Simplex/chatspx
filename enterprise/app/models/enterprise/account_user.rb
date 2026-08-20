module Enterprise::AccountUser
  def permissions
    # supervision_permissions entra aqui também: o ramo do custom_role não chama super,
    # e sem isso um supervisor com papel customizado perderia a permissão team_supervisor.
    custom_role.present? ? (custom_role.permissions + ['custom_role'] + supervision_permissions) : super
  end
end
