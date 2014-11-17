module Spree
  class GoogleProduct < ActiveRecord::Base
    G_ATTRIBUTES = [
      :offer_id, :title, :description, :google_product_category, :product_type,
      :link, :mobile_link, :image_link, :additional_image_link, :condition,

      :availability, :availability_date, :price, :sale_price,
      :sale_price_effective_date,

      :brand, :gtin, :mpn, :identifier_exists, :gender, :age_group,
      :size_type, :size_system,

      :color, :size,

      :material, :pattern, :item_group_id,

      :tax, :shipping, :shipping_weight, :shipping_label,

      :multipack, :is_bundle,

      :adult, :adwords_grouping, :adwords_labels, :adwords_redirect,

      :excluded_destination, :expiration_date,

      :content_language, :target_country, :channel
    ]

    belongs_to :variant, class_name: 'Spree::Variant'

    def self.configure
      yield GoogleProduct::Attributes.instance
    end

    def attributes_hash(camelize_keys = false)
      G_ATTRIBUTES.map do |attribute|
        value = Attributes.instance.value_of(variant, attribute)
        next if value.nil?
        key = camelize_keys ? camelize(attribute.to_s) : attribute
        next key, value
      end
        .compact
        .to_h
        .with_indifferent_access
    end

    def attributes_json
      attributes_hash(true).to_json
    end

    def status
      raise 'implement me plz'
    end

    def google_get
      return nil unless has_product_id?

      refresh_if_unauthorized do
        api_client.execute(
          api_method: google_shopping.products.get,
          parameters: {
            'merchantId' => settings.merchant_id,
            'productId' => product_id
          }
        )
      end
    end

    def google_insert
      refresh_if_unauthorized do
        api_client.execute(
          api_method: google_shopping.products.insert,
          parameters: { 'merchantId' => settings.merchant_id },
          body_object: attributes_hash(true)
        )
      end
    end

    def google_delete
      return unless has_product_id?

      refresh_if_unauthorized do
        api_client.execute(
          api_method: google_shopping.products.delete,
          parameters: {
            'merchantId' => settings.merchant_id,
            'productId' => product_id
          }
        )
      end
    end

    def has_product_id?
      !(product_id.nil? || product_id.empty?)
    end

    def merchant_center_link
      return unless has_product_id?

      "https://google.com/merchants/view?"\
      "merchantOfferId=#{variant.sku}&channel=0&country=US*language=en"
    end

    protected

    def bad_credential_errors_from(response)
      response.data.try(:error).try(:find) do |error|
        error['reason']  == 'authError' &&
        error['message'] == 'Invalid Credentials'
      end
    end

    def errors_from(response)
      response.data.try(:error)
                   .try(:[], 'errors')
                   .try(:to_json)
    end

    def refresh_if_unauthorized
      response = yield
      auth_error = bad_credential_errors_from(response)

      if auth_error
        if api_client.authorization.refresh_token
          if settings.update_from(api_client.authorization.refresh!)
            puts 'Got bad authorization from Google. Refreshing token...'
            response = yield
            if bad_credential_errors_from(response)
              puts 'Still no dice on authentication!'
            end
          end
        else
          logger.warn("No refresh token; OAuth authentication required.")
        end
      end

      self.last_insertion_errors = errors_from(response)
      self.last_insertion_date = Time.now
      # TODO so if product?(response), we should assign self.product_id to 
      # response.data.id.
      # Additionally, we should maybe assign last_insertion_errors to 
      # response.data.warnings, or make a last_insertion_warnings field in
      # this model, so that people can see the warnings for any given variant.
      # Get that done, and start incorperating self.automatically_update, and
      # maybe make a view for manually updating variants.
      save!
      response
    end

    def product?(response)
      response.data.is_a?(Google::APIClient::Schema::Content::V2::Product)
    end

    def settings
      @gts_settings ||= GoogleShoppingSetting.instance
    end

    def api_client
      @api_client ||= Google::APIClient.new(
          application_name: settings.google_api_appplication_name || 'Spree',
          generate_authenticated_request: :oauth_2,
          auto_refresh_token: true
        ).tap(&settings.method(:set_api_client_info))
    end

    def google_shopping
      @google_shopping ||= api_client.discovered_api('content', 'v2')
    end

    def camelize(key)
      case key
      when 'additional_image_link' then 'additionalImageLinks'
      else key.camelize(:lower)
      end
    end
  end
end
