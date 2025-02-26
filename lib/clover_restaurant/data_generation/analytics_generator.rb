require_relative "base_generator"

module CloverRestaurant
  module DataGeneration
    class AnalyticsGenerator < BaseGenerator
      def generate_period_summary(days_data, start_date, days_count)
        log_info("Generating summary for period from #{start_date} to #{start_date + days_count - 1}")

        # Initialize summary data
        summary = {
          period_start: start_date,
          period_end: start_date + days_count - 1,
          total_days: days_count,
          total_orders: 0,
          total_revenue: 0,
          total_refunds: 0,
          total_net_revenue: 0,
          total_customers_served: 0,
          total_items_sold: 0,
          average_order_value: 0,
          busiest_day: nil,
          busiest_day_orders: 0,
          top_selling_items: {},
          employee_order_counts: {},
          daily_revenue: []
        }

        # Process each day
        days_data.each do |day|
          day_date = day[:date]
          day_orders = day[:orders]
          day_revenue = 0
          day_refunds = 0

          # Skip if outside our period
          next if day_date < start_date || day_date > (start_date + days_count - 1)

          summary[:total_orders] += day_orders.size

          # Process each order
          day_orders.each do |order|
            # Revenue
            order_total = order["total"] || 0
            day_revenue += order_total

            # Customers
            summary[:total_customers_served] += 1 if order["customer"] && order["customer"]["id"]

            # Items
            if order["lineItems"] && order["lineItems"]["elements"]
              order["lineItems"]["elements"].each do |line_item|
                item_name = line_item["name"]
                item_quantity = line_item["quantity"] || 1

                summary[:total_items_sold] += item_quantity

                # Track for top sellers
                summary[:top_selling_items][item_name] ||= 0
                summary[:top_selling_items][item_name] += item_quantity
              end
            end

            # Employee tracking
            next unless order["employee"] && order["employee"]["id"]

            employee_id = order["employee"]["id"]
            employee_name = order["employee"]["name"] || "Employee #{employee_id}"

            summary[:employee_order_counts][employee_name] ||= 0
            summary[:employee_order_counts][employee_name] += 1
          end

          # Process refunds
          day[:refunds].each do |refund|
            refund_amount = refund["amount"] || 0
            day_refunds += refund_amount
          end

          # Update daily revenue tracking
          summary[:daily_revenue] << {
            date: day_date,
            revenue: day_revenue,
            refunds: day_refunds,
            net_revenue: day_revenue - day_refunds
          }

          # Update totals
          summary[:total_revenue] += day_revenue
          summary[:total_refunds] += day_refunds

          # Check if busiest day
          if day_orders.size > summary[:busiest_day_orders]
            summary[:busiest_day] = day_date
            summary[:busiest_day_orders] = day_orders.size
          end
        end

        # Calculate net revenue
        summary[:total_net_revenue] = summary[:total_revenue] - summary[:total_refunds]

        # Calculate average order value
        if summary[:total_orders] > 0
          summary[:average_order_value] = (summary[:total_revenue].to_f / summary[:total_orders]).round(2)
        end

        # Sort top selling items and keep top 10
        sorted_items = summary[:top_selling_items].sort_by { |_, count| -count }
        summary[:top_selling_items] = Hash[sorted_items.take(10)]

        # Sort employees by order count
        sorted_employees = summary[:employee_order_counts].sort_by { |_, count| -count }
        summary[:employee_order_counts] = Hash[sorted_employees]

        summary
      end
    end
  end
end
