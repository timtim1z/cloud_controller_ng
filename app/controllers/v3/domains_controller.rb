require 'messages/domain_create_message'
require 'messages/domains_list_message'
require 'presenters/v3/domain_presenter'
require 'actions/domain_create'
require 'fetchers/domain_list_fetcher'

class DomainsController < ApplicationController
  def index
    message = DomainsListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?
    guids = permission_queryer.readable_org_guids_for_domains
    dataset = DomainListFetcher.new.fetch(guids)
    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::DomainPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/domains',
      message: message,
    )
  end

  def create
    message = DomainCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    if create_scoped_domain_request?(message)
      check_create_scoped_domain_permissions!(message)
    else
      unauthorized! unless permission_queryer.can_write_globally?
    end

    domain = DomainCreate.new.create(message: message)

    render status: :created, json: Presenters::V3::DomainPresenter.new(domain)
  rescue DomainCreate::Error => e
    unprocessable!(e)
  end

  private

  def check_create_scoped_domain_permissions!(message)
    unprocessable_org!(message.organization_guid) unless Organization.find(guid: message.organization_guid)

    unauthorized! unless permission_queryer.can_write_to_org?(message.organization_guid)

    FeatureFlag.raise_unless_enabled!(:private_domain_creation) unless permission_queryer.can_write_globally?
  end

  def create_scoped_domain_request?(message)
    message.requested?(:relationships)
  end

  def unprocessable_org!(org_guid)
    unprocessable!("Organization with guid '#{org_guid}' does not exist or you do not have access to it.")
  end
end
