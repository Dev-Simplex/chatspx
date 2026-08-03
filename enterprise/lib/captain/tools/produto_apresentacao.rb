# Resolve o produto do lead e o inventário de apresentação dele. Compartilhado pelas duas tools
# de peça (listar e enviar) para que ambas enxerguem EXATAMENTE o mesmo produto — se divergissem,
# a IA listaria de um e enviaria de outro.
module Captain::Tools::ProdutoApresentacao
  private

  def produto_do_lead(conversation)
    slug = ::Spx::Distribuicao::ResolverProdutoService.new(conversation).call
    return nil if slug.blank?

    ::Spx::Distribuicao::Produto.ativos.find_by(account_id: conversation.account_id, slug: slug)
  end
end
