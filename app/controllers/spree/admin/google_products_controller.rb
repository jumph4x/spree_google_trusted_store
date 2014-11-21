module Spree
  module Admin
    class GoogleProductsController < Spree::Admin::ResourceController
      def show
        redirect_to action: :edit
      end

      def edit
        @google_product = GoogleProduct.find(params[:id])
        render 'edit', locals: locals
      end

      def update
        @google_product = GoogleProduct.find(params[:id])

        finish = -> { redirect_to action: 'edit' }

        if @google_product.update_attributes permitted_params[:google_product]
          update_flash :success, "Successfully updated local properties."
        else
          update_flash :error, @google_product.errors.full_messages.join(', ')
          finish = -> { render 'edit', locals: locals }
        end
        if params[:do_insert] && params[:do_insert].include?('Upload')
          response = @google_product.google_insert 

          if errors_in?(response)
            update_flash :error, 'Failed to upload to Google'
          else
            update_flash :success, 'Successfully uploaded to Google!'
          end
        end
        
        finish.call
      end

      private

      def update_flash(key, value)
        if key == :success && flash_okay?(:error)
          flash[:error] = "(Error) #{flash[:error]} ; (Success) #{value}"
        elsif key == :error && flash_okay?(:success)
          success = flash[:success]
          flash[:success] = nil
          flash[:error] = "(Error) #{value}; (Success) #{success}"
        elsif flash_okay?(key)
          flash[key] += ", #{value}"
        else
          flash[key] = value
        end
      end

      def flash_okay?(key)
        return false if flash[key].nil?
        return false if flash[key].empty?
        return true
      end

      def errors_in?(response)
        begin
          !(response.data.error['errors'].nil? ||
            response.data.error['errors'].empty?)
        rescue NoMethodError
          false
        end
      end

      def locals
        {
          google_product: @google_product,
          variant: @google_product.variant
        }
      end

      def permitted_params
        params.permit(
          :do_insert,
          google_product: Spree::GoogleProduct::Attributes.instance
            .db_field_names + %i(
              automatically_update
            )
        )
      end
    end
  end
end
