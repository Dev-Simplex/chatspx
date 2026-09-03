raise "BANCO ERRADO" unless ActiveRecord::Base.connection.current_database == 'chatwoot_val_o1backend'
CustomAttributeDefinition.where(attribute_key: 'carrinho_valor').destroy_all
c = Conversation.first
c.update_columns(custom_attributes: { 'plano' => 'pro' })
u = User.first
u.ui_settings = (u.ui_settings || {}).merge('is_contact_sidebar_open' => true, 'is_conv_details_open' => true,
                                            'show_all_attributes_conversation_panel' => true)
u.ui_settings.delete('conversation_elements_order_conversation_panel')
u.save!
# O fork limita sessoes ativas por usuario (sessions_controller.rb:149). Cada
# execucao do navegador abre uma; sem limpar, a de numero N+1 recebe 409 e o
# login para de funcionar no meio da validacao.
UserSession.delete_all
puts "reset ok · definicoes=#{CustomAttributeDefinition.pluck(:attribute_key)}"
