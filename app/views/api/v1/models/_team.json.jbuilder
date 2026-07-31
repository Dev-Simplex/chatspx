json.id resource.id
json.name resource.name
json.description resource.description
json.allow_auto_assign resource.allow_auto_assign
json.account_id resource.account_id
json.is_member (@current_user_team_ids || Current.user.team_ids.to_set).include?(resource.id)
# supervisão é ortogonal a ser membro (D1): dá visibilidade das conversas do time sem entrar na equipe
json.is_supervisor (@current_user_supervised_team_ids || TeamSupervision.team_ids(Current.user, Current.account).to_set).include?(resource.id)
