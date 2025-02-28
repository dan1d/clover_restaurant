# CloverRestaurant

A comprehensive Ruby gem for interacting with the Clover API, designed specifically for restaurant operations.

## Overview

CloverRestaurant provides a complete suite of tools for managing all aspects of a restaurant business through the Clover API, including:

- Complete inventory management (items, categories, modifiers)
- Order processing and payment handling
- Employee management and shift tracking
- Customer relationship management
- Table and reservation management
- Menu creation and organization
- Discount and tax rate configuration
- Data generation for testing and simulation

The gem also includes powerful simulation capabilities that can generate realistic business data over extended periods, making it perfect for testing, demonstrations, and development environments.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'clover_restaurant'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install clover_restaurant
```

## Configuration

Configure the gem with your Clover API credentials:

```ruby
CloverRestaurant.configure do |config|
  config.merchant_id = 'YOUR_MERCHANT_ID'
  config.api_token = 'YOUR_API_TOKEN'  # OAuth token
  # OR
  config.api_key = 'YOUR_API_KEY'      # API key (preferred)
  config.environment = 'https://sandbox.dev.clover.com/'  # Use 'https://api.clover.com/' for production
  config.log_level = Logger::INFO
end
```

## Usage

### Service Manager

CloverRestaurant provides a convenient service manager to access all functionality:

```ruby
# Get the service manager
services = CloverRestaurant.services

# Access individual services
inventory_service = services.inventory
order_service = services.order
customer_service = services.customer
# and so on...

# You can also initialize services directly
inventory_service = CloverRestaurant::Services::InventoryService.new
```

### Inventory Management

```ruby
# Get all items
items = services.inventory.get_items

# Create a new item
item = services.inventory.create_item({
  'name' => 'Margherita Pizza',
  'price' => 1495,  # $14.95
  'priceType' => 'FIXED',
  'cost' => 500,   # $5.00 cost
  'sku' => 'PIZZA-001'
})

# Generate random restaurant inventory
inventory = services.inventory.create_random_restaurant_inventory(5, 10)
# Creates 5 categories with about 10 items each
```

### Order Management

```ruby
# Create a new order
order = services.order.create_order

# Add an item to the order
line_item = services.order.add_line_item(order['id'], item_id, 2)  # Add 2 of the item

# Add a discount to the order
discount = services.discount.create_discount({
  'name' => 'Happy Hour',
  'percentage' => 15
})

services.order.add_discount(order['id'], { 'discount' => { 'id' => discount['id'] } })

# Create a random order with random items
random_order = services.order.create_random_order(items)
```

### Payment Processing

```ruby
# Process a card payment
payment = services.payment.simulate_card_payment(order['id'], 2495)

# Add a tip
services.tip.add_tip_to_payment(payment['id'], 500)  # $5.00 tip
```

### Table Management

```ruby
# Create a standard restaurant layout
layout = services.table.create_standard_restaurant_layout("Main Dining Room")

# Assign an order to a table
services.table.assign_order_to_table(order['id'], table_id)

# Get table status
status = services.table.get_table_status
```

### Reservations

```ruby
# Make a reservation
reservation = services.reservation.make_customer_reservation(
  { 'firstName' => 'John', 'lastName' => 'Smith', 'phoneNumber' => '555-123-4567' },
  DateTime.now + 2,  # 2 days from now
  4                  # Party of 4
)

# Find available tables
available_tables = services.reservation.find_available_tables(DateTime.now + 2, 4)

# Generate random reservations for testing
random_reservations = services.reservation.create_random_reservations(10)
```

### Employees

```ruby
# Create standard roles
roles = services.employee.create_standard_restaurant_roles

# Create random employees
employees = services.employee.create_random_employees(5, roles)

# Clock in an employee
shift = services.employee.clock_in(employee_id)

# Clock out
services.employee.clock_out(shift['id'])
```

### Customers

```ruby
# Create or update a customer
customer = services.customer.create_or_update_customer({
  'firstName' => 'Jane',
  'lastName' => 'Doe',
  'phoneNumber' => '555-987-6543',
  'emailAddress' => 'jane.doe@example.com'
})

# Generate random customers for testing
random_customers = services.customer.create_random_customers(10)
```

### Menu Management

```ruby
# Create a standard menu from your inventory
menu = services.menu.create_standard_menu("Dinner Menu")

# Create time-based menus
time_menus = services.menu.create_time_based_menus

# Print a menu
menu_text = services.menu.print_menu(menu['id'])
```

### Modifiers

```ruby
# Create common modifier groups
modifier_groups = services.modifier.create_common_modifier_groups

# Assign modifiers to appropriate items
services.modifier.assign_appropriate_modifiers_to_items(items)
```

### Discounts

```ruby
# Create standard discounts
discounts = services.discount.create_standard_discounts

# Apply a random discount to an order
services.discount.apply_random_discount_to_order(order['id'])
```

### Tax Rates

```ruby
# Create standard tax rates
tax_rates = services.tax_rate.create_standard_tax_rates

# Assign appropriate tax rates to categories
services.tax_rate.assign_category_tax_rates(categories, tax_rates)
```

## Data Generation and Simulation

CloverRestaurant includes robust data generation capabilities for creating test environments and simulations.

### Creating a Complete Restaurant Setup

```ruby
# Initialize the entity generator to create all required entities
services.create_entities
```

This will create:
- Inventory with categories and items
- Modifier groups assigned to appropriate items
- Standard tax rates
- Standard discounts
- Employee roles and employees
- Customers
- Table layout
- Menus

### Running a Business Simulation

The gem includes a `RestaurantGenerator` for simulating business operations over time:

```ruby
# Create the restaurant generator
generator = CloverRestaurant::DataGeneration::RestaurantGenerator.new

# Setup the restaurant
generator.setup_restaurant("Claude's Bistro")

# Simulate a business day
day_data = generator.simulate_business_day(Date.today)

# Analyze the results
analytics = CloverRestaurant::DataGeneration::AnalyticsGenerator.new
summary = analytics.generate_period_summary([day_data], Date.today, 1)
```

You can also use the provided simulation script:

```bash
$ ruby simulate_restaurant.rb
```

This script will:
1. Set up a complete restaurant in your Clover account
2. Simulate a configurable number of business days
3. Generate orders, payments, and refunds
4. Produce a detailed analysis of the simulated period

## Project Structure

The gem is organized into the following modules:

- `CloverRestaurant::Services`: Base API service classes for Clover endpoints
- `CloverRestaurant::DataGeneration`: Tools for generating test data and simulations
- `CloverRestaurant::CloverServicesManager`: Central access point for all services

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
