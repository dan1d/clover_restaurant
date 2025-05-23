require_relative 'base_simulator'
require_relative 'entity_setup'

module CloverRestaurant
  module Simulator
    class RestaurantSimulator < BaseSimulator
      def run(options = {})
        print_header

        begin
          setup_restaurant(options)
          print_summary
        rescue StandardError => e
          handle_error(e)
          exit 1
        end
      end

      def delete_everything
        puts "\n🚨 Deleting all Clover entities...".colorize(:light_blue)
        @entity_generator.delete_all_entities
        puts "✅ All Clover entities deleted successfully."
      end

      private

      def setup_restaurant(options)
        entity_setup = EntitySetup.new(@services_manager, @state, @logger)
        entity_setup.setup_entities(options)
      end

      def print_summary
        summary = @state.get_creation_summary

        table = Terminal::Table.new do |t|
          t.title = "Setup Summary"
          t.headings = ['Entity Type', 'Count']

          summary.each do |type, count|
            t.add_row [type, count]
          end
        end

        puts "\n" + table.to_s + "\n"
      end

      def handle_error(error)
        @logger.error "FATAL ERROR: #{error.message}"
        @logger.error error.backtrace.join("\n")

        # Save error state
        @state.mark_step_completed('last_error', {
          message: error.message,
          time: Time.now.iso8601
        })
      end
    end
  end
end
