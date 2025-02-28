# lib/clover_restaurant/data_generation/analytics_generator.rb
module CloverRestaurant
  module DataGeneration
    class AnalyticsGenerator
      def generate_period_summary(days_data, start_date, total_days)
        # Initialize summary object
        summary = {
          period_start: start_date.to_s,
          period_end: (start_date + total_days - 1).to_s,
          total_days: total_days,
          total_orders: 0,
          total_revenue: 0,
          total_refunds: 0,
          total_net_revenue: 0,
          average_order_value: 0,
          total_customers_served: Set.new,
          total_items_sold: 0,
          top_selling_items: {},
          busiest_day: nil,
          busiest_day_orders: 0,
          employee_order_counts: {},
          daily_revenue: []
        }

        # Temporary storage for aggregating data
        all_items_sold = Hash.new(0)

        # Process each day's data
        days_data.each do |day|
          next unless day[:date] # Skip days with no date

          # Count orders
          day_order_count = day[:orders].size
          summary[:total_orders] += day_order_count

          # Track revenue
          summary[:total_revenue] += day[:total_revenue]
          summary[:total_refunds] += day[:total_refunds]

          # Track customers
          summary[:total_customers_served].merge(day[:customers_served])

          # Track sales by item
          day[:items_sold].each do |item_name, quantity|
            all_items_sold[item_name] += quantity
            summary[:total_items_sold] += quantity
          end

          # Track employee performance
          day[:employee_orders].each do |employee_name, order_count|
            summary[:employee_order_counts][employee_name] ||= 0
            summary[:employee_order_counts][employee_name] += order_count
          end

          # Track busiest day
          if day_order_count > summary[:busiest_day_orders]
            summary[:busiest_day] = day[:date].to_s
            summary[:busiest_day_orders] = day_order_count
          end

          # Add to daily revenue data
          summary[:daily_revenue] << {
            date: day[:date],
            revenue: day[:total_revenue],
            net_revenue: day[:total_revenue] - day[:total_refunds]
          }
        end

        # Calculate net revenue
        summary[:total_net_revenue] = summary[:total_revenue] - summary[:total_refunds]

        # Calculate average order value
        summary[:average_order_value] = if summary[:total_orders] > 0
                                          (summary[:total_revenue].to_f / summary[:total_orders]).round
                                        else
                                          0
                                        end

        # Get top selling items
        summary[:top_selling_items] = all_items_sold.sort_by { |_, quantity| -quantity }.first(10).to_h

        # Sort employee data by number of orders
        summary[:employee_order_counts] = summary[:employee_order_counts].sort_by { |_, count| -count }.to_h

        # Convert customer set to count
        summary[:total_customers_served] = summary[:total_customers_served].size

        # Sort daily revenue by date
        summary[:daily_revenue].sort_by! { |day| day[:date] }

        summary
      end

      def generate_sales_report(days_data, start_date, end_date)
        # Filter data to date range
        filtered_days = days_data.select { |day| day[:date] >= start_date && day[:date] <= end_date }

        # Initialize report
        report = {
          period: {
            start_date: start_date,
            end_date: end_date,
            days: (end_date - start_date + 1).to_i
          },
          totals: {
            revenue: 0,
            refunds: 0,
            net_revenue: 0,
            orders: 0,
            average_order_value: 0
          },
          items: {
            total_sold: 0,
            by_category: {},
            top_sellers: []
          },
          employees: {
            top_performers: []
          },
          customers: {
            total_served: Set.new,
            repeat_visits: 0,
            new_customers: 0
          },
          daily: []
        }

        # Item tracking
        all_items_sold = Hash.new(0)
        employee_orders = Hash.new(0)
        customer_visits = Hash.new(0)

        # Process each day
        filtered_days.each do |day|
          # Skip if no date
          next unless day[:date]

          # Daily revenue
          daily_data = {
            date: day[:date],
            revenue: day[:total_revenue],
            refunds: day[:total_refunds],
            net_revenue: day[:total_revenue] - day[:total_refunds],
            orders: day[:orders].size,
            customers: day[:customers_served].size
          }

          report[:daily] << daily_data

          # Add to totals
          report[:totals][:revenue] += day[:total_revenue]
          report[:totals][:refunds] += day[:total_refunds]
          report[:totals][:net_revenue] += (day[:total_revenue] - day[:total_refunds])
          report[:totals][:orders] += day[:orders].size

          # Count items sold
          day[:items_sold].each do |item_name, quantity|
            all_items_sold[item_name] += quantity
            report[:items][:total_sold] += quantity
          end

          # Track employee performance
          day[:employee_orders].each do |employee_name, order_count|
            employee_orders[employee_name] += order_count
          end

          # Track customer visits
          day[:customers_served].each do |customer_id|
            customer_visits[customer_id] += 1
            report[:customers][:total_served] << customer_id
          end
        end

        # Calculate average order value
        report[:totals][:average_order_value] = if report[:totals][:orders] > 0
                                                  (report[:totals][:revenue].to_f / report[:totals][:orders]).round
                                                else
                                                  0
                                                end

        # Get top selling items
        report[:items][:top_sellers] = all_items_sold.sort_by { |_, quantity| -quantity }.first(10).to_a

        # Get top performing employees
        report[:employees][:top_performers] = employee_orders.sort_by { |_, count| -count }.first(5).to_a

        # Customer metrics
        report[:customers][:total_served] = report[:customers][:total_served].size
        report[:customers][:repeat_visits] = customer_visits.values.count { |visits| visits > 1 }

        report
      end

      def generate_item_sales_report(days_data, start_date, end_date)
        # Filter data to date range
        filtered_days = days_data.select { |day| day[:date] >= start_date && day[:date] <= end_date }

        # Initialize report
        report = {
          period: {
            start_date: start_date,
            end_date: end_date,
            days: (end_date - start_date + 1).to_i
          },
          items: {},
          total_items_sold: 0
        }

        # Process each day
        filtered_days.each do |day|
          # Skip if no date
          next unless day[:date]

          # Count items sold
          day[:items_sold].each do |item_name, quantity|
            report[:items][item_name] ||= {
              total_quantity: 0,
              daily_sales: {}
            }

            report[:items][item_name][:total_quantity] += quantity
            report[:items][item_name][:daily_sales][day[:date]] = quantity
            report[:total_items_sold] += quantity
          end
        end

        # Calculate average daily sales for each item
        report[:items].each do |item_name, data|
          data[:avg_daily_sales] = (data[:total_quantity].to_f / report[:period][:days]).round(2)
          data[:percentage_of_total] = (data[:total_quantity].to_f / report[:total_items_sold] * 100).round(2)
        end

        report
      end
    end
  end
end
