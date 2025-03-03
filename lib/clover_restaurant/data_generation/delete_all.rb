require "json"
require_relative "base_generator"

module CloverRestaurant
  module DataGeneration
    class DeleteAll < BaseGenerator
      def initialize(custom_config = nil, services_manager)
        super(custom_config)
        @services_manager = services_manager

        @services = {
          inventory: @services_manager.inventory,
          modifier: @services_manager.modifier,
          # employee: @services_manager.employee,
          customer: @services_manager.customer,
          discount: @services_manager.discount,
          tax: @services_manager.tax,
          payment: @services_manager.payment
        }

        @entity_cache = {}
      end

      def delete_all_entities
        delete_all_orders
        delete_all_customers
        delete_all_items
        delete_all_categories
        # delete_all_employees
        # delete_all_tables
        delete_all_payments
      end

      private

      def delete_all_orders
        orders = @services_manager.order.get_orders["elements"]
        orders.each do |order|
          @services_manager.order.delete_order(order["id"])
        end
      end

      def delete_all_customers
        customers = @services_manager.customer.get_customers["elements"]
        customers.each do |customer|
          @services_manager.customer.delete_customer(customer["id"])
        end
      end

      def delete_all_items
        items = @services_manager.inventory.get_items["elements"]
        items.each do |item|
          @services_manager.inventory.delete_item(item["id"])
        end
      end

      def delete_all_categories
        categories = @services_manager.inventory.get_categories["elements"]
        categories.each do |category|
          @services_manager.inventory.delete_category(category["id"])
        end
      end

      def delete_all_employees
        employees = @services_manager.employee.get_employees["elements"]
        employees.each do |employee|
          @services_manager.employee.delete_employee(employee["id"])
        end
      end

      def delete_all_refunds
        refunds = @services_manager.refund.get_refunds["elements"]
        refunds.each do |refund|
          @services_manager.refund.delete_refund(refund["id"])
        end
      end

      def delete_all_tax_rates
        tax_rates = @services_manager.tax_rate.get_tax_rates["elements"]
        tax_rates.each do |tax_rate|
          @services_manager.tax_rate.delete_tax_rate(tax_rate["id"])
        end
      end

      def delete_all_payments
        payments = @services_manager.payment.get_payments
        payments.each do |payment|
          @services_manager.payment.delete_payment(payment["id"])
        end
      end
    end
  end
end
