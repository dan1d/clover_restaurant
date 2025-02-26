# CloverRestaurant

A comprehensive Ruby gem for interacting with the Clover API, designed specifically for restaurant operations.

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

The gem provides service classes for all aspects of restaurant operations:

### Inventory Management

```ruby
# Create inventory service
inventory_service = CloverRestaurant::InventoryService.new

# Get all items
items = inventory_service.get_items

# Create a new item
item = inventory_service.create_item({
  'name' => 'Margherita Pizza',
  'price' => 1495,  # $14.95
  'priceType' => 'FIXED',
  'cost' => 500,   # $5.00 cost
  'sku' => 'PIZZA-001'
})

# Generate random restaurant inventory
inventory = inventory_service.create_random_restaurant_inventory(5, 10)
# Creates 5 categories with about 10 items each
```

### Order Management

```ruby
# Create order service
order_service = CloverRestaurant::OrderService.new

# Create a new order
order = order_service.create_order

# Add an item to the order
line_item = order_service.add_line_item(order['id'], item_id, 2)  # Add 2 of the item

# Add a discount to the order
discount_service = CloverRestaurant::DiscountService.new
discount = discount_service.create_discount({
  'name' => 'Happy Hour',
  'percentage' => 15
})

order_service.add_discount(order['id'], { 'discount' => { 'id' => discount['id'] } })

# Create a random order with random items
random_order = order_service.create_random_order(items)
```

### Payment Processing

```ruby
# Create payment service
payment_service = CloverRestaurant::PaymentService.new

# Process a card payment
payment = payment_service.simulate_card_payment(order['id'], 2495)

# Add a tip
tip_service = CloverRestaurant::TipService.new
tip_service.add_tip_to_payment(payment['id'], 500)  # $5.00 tip
```

### Table Management

```ruby
# Create table service
table_service = CloverRestaurant::TableService.new

# Create a standard restaurant layout
layout = table_service.create_standard_restaurant_layout("Main Dining Room")

# Assign an order to a table
table_service.assign_order_to_table(order['id'], table_id)

# Get table status
status = table_service.get_table_status
```

### Reservations

```ruby
# Create reservation service
reservation_service = CloverRestaurant::ReservationService.new

# Make a reservation
reservation = reservation_service.make_customer_reservation(
  { 'firstName' => 'John', 'lastName' => 'Smith', 'phoneNumber' => '555-123-4567' },
  DateTime.now + 2,  # 2 days from now
  4                  # Party of 4
)

# Find available tables
available_tables = reservation_service.find_available_tables(DateTime.now + 2, 4)

# Generate random reservations for testing
random_reservations = reservation_service.create_random_reservations(10)
```

### Employees

```ruby
# Create employee service
employee_service = CloverRestaurant::EmployeeService.new

# Create standard roles
roles = employee_service.create_standard_restaurant_roles

# Create random employees
employees = employee_service.create_random_employees(5, roles)

# Clock in an employee
shift = employee_service.clock_in(employee_id)

# Clock out
employee_service.clock_out(shift['id'])
```

### Customers

```ruby
# Create customer service
customer_service = CloverRestaurant::CustomerService.new

# Create or update a customer
customer = customer_service.create_or_update_customer({
  'firstName' => 'Jane',
  'lastName' => 'Doe',
  'phoneNumber' => '555-987-6543',
  'emailAddress' => 'jane.doe@example.com'
})

# Generate random customers for testing
random_customers = customer_service.create_random_customers(10)
```

### Menu Management

```ruby
# Create menu service
menu_service = CloverRestaurant::MenuService.new

# Create a standard menu from your inventory
menu = menu_service.create_standard_menu("Dinner Menu")

# Create time-based menus
time_menus = menu_service.create_time_based_menus

# Print a menu
menu_text = menu_service.print_menu(menu['id'])
```

### Modifiers

```ruby
# Create modifier service
modifier_service = CloverRestaurant::ModifierService.new

# Create common modifier groups
modifier_groups = modifier_service.create_common_modifier_groups

# Assign modifiers to appropriate items
modifier_service.assign_appropriate_modifiers_to_items(items)
```

### Discounts

```ruby
# Create discount service
discount_service = CloverRestaurant::DiscountService.new

# Create standard discounts
discounts = discount_service.create_standard_discounts

# Apply a random discount to an order
discount_service.apply_random_discount_to_order(order['id'])
```

### Tax Rates

```ruby
# Create tax rate service
tax_service = CloverRestaurant::TaxRateService.new

# Create standard tax rates
tax_rates = tax_service.create_standard_tax_rates

# Assign appropriate tax rates to categories
tax_service.assign_category_tax_rates(categories, tax_rates)
```

## Creating a Complete Restaurant

```ruby
# Initialize all services
inventory_service = CloverRestaurant::InventoryService.new
modifier_service = CloverRestaurant::ModifierService.new
employee_service = CloverRestaurant::EmployeeService.new
customer_service = CloverRestaurant::CustomerService.new
table_service = CloverRestaurant::TableService.new
menu_service = CloverRestaurant::MenuService.new
discount_service = CloverRestaurant::DiscountService.new
tax_service = CloverRestaurant::TaxRateService.new
reservation_service = CloverRestaurant::ReservationService.new

# Step 1: Create inventory with categories and items
inventory = inventory_service.create_random_restaurant_inventory(5, 10)

# Step 2: Create modifier groups and assign to items
modifier_groups = modifier_service.create_common_modifier_groups
modifier_service.assign_appropriate_modifiers_to_items(inventory[:items])

# Step 3: Create tax rates and assign to categories
tax_rates = tax_service.create_standard_tax_rates
tax_service.assign_category_tax_rates(inventory[:categories], tax_rates)

# Step 4: Create standard discounts
discounts = discount_service.create_standard_discounts

# Step 5: Create employee roles and employees
roles = employee_service.create_standard_restaurant_roles
employees = employee_service.create_random_employees(10, roles)

# Step 6: Create customers
customers = customer_service.create_random_customers(20)

# Step 7: Create table layout
layout = table_service.create_standard_restaurant_layout("Main Restaurant")

# Step 8: Create menus
standard_menu = menu_service.create_standard_menu("Main Menu", inventory[:categories], inventory[:items])
time_menus = menu_service.create_time_based_menus(inventory[:items])

# Step 9: Create some reservations
reservations = reservation_service.create_random_reservations(15)

puts "Restaurant setup complete!"
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
