# Clover Restaurant Gem

A Ruby gem that provides a clean interface for interacting with Clover POS restaurant data in sandbox environments. This gem facilitates the extraction and transformation of restaurant data from Clover's API for integration with QuickBooks.

## Features

- Simplified Clover API client for restaurant data
- Sandbox environment support for testing
- Data models for common restaurant entities
- Sales data aggregation and transformation
- Category and menu item mapping utilities

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'clover_restaurant'
```

And then execute:

```bash
bundle install
```

## Usage

```ruby
# Initialize the client
client = CloverRestaurant::Client.new(
  api_key: 'your_api_key',
  merchant_id: 'your_merchant_id',
  sandbox: true
)

# Fetch daily sales
sales = client.daily_sales(date: Date.today)

# Get menu categories
categories = client.categories

# Get menu items
items = client.menu_items

# Get payment methods
payments = client.payment_methods
```

## Configuration

```ruby
CloverRestaurant.configure do |config|
  config.sandbox = true # Use Clover sandbox environment
  config.api_version = 'v3'
  config.timeout = 30 # API timeout in seconds
end
```

## Data Models

- `CloverRestaurant::Sale`
- `CloverRestaurant::Category`
- `CloverRestaurant::MenuItem`
- `CloverRestaurant::PaymentMethod`
- `CloverRestaurant::Modifier`

## Development

1. Clone the repository
2. Run `bundle install`
3. Run `rake spec` to run the tests
4. Create a new branch for your feature
5. Submit a pull request

## Related Projects

- `clover_quickbooks_sync_api` - Main Rails API using this gem
- `clover-quickbooks-react-ui` - Frontend interface
