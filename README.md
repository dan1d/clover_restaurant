# Clover Restaurant Gem & Simulator

This project provides a Ruby gem, `clover_restaurant`, designed to interact with the Clover POS API. It includes a simulator script, `simulate_restaurant.rb`, that creates a comprehensive restaurant setup in your Clover merchant account with realistic data, perfect for testing integrations, demos, or development.

**For a deep dive into the simulator's features, entity creation flow, recent changes, troubleshooting, and the gem's service architecture, please refer to the `AI.MD` file in the project root.**

## Prerequisites

1.  **Ruby Environment:** Ruby 2.7+ recommended.
2.  **Bundler:** Install with `gem install bundler`.
3.  **Project Dependencies:** Navigate to the project root and run `bundle install`.
4.  **Clover API Credentials:** Create a `.env` file in the project root with your Clover Sandbox API token and Merchant ID:
    ```env
    CLOVER_API_TOKEN=your_sandbox_api_token
    CLOVER_MERCHANT_ID=your_merchant_id
    # Optional: CLOVER_ENVIRONMENT=https://api.clover.com/ (if using production, otherwise defaults to sandbox)
    ```

## How to Run the Simulator (`simulate_restaurant.rb`)

The primary utility is the `simulate_restaurant.rb` script which always performs a clean setup of a restaurant environment.

1.  **Navigate to the project directory:**
    ```bash
    cd clover_restaurant
    ```
2.  **Ensure the script is executable:**
    ```bash
    chmod +x simulate_restaurant.rb
    ```
3.  **Basic setup (creates all restaurant entities like menu, staff, etc.):**
    ```bash
    ./simulate_restaurant.rb
    ```
4.  **Setup with historical orders/payments:**
    ```bash
    ./simulate_restaurant.rb --generate-orders
    ```

## Gem Development Workflow

If you make changes to the gem's source code (e.g., in the `lib/` directory):

1.  **Build the gem:**
    ```bash
    gem build clover_restaurant.gemspec
    ```
2.  **Install the newly built gem version (replace `0.1.0` with the current version if different):**
    ```bash
    gem install ./clover_restaurant-0.1.0.gem
    ```
3.  **Run the simulator (or your tests) to use the changes.**

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

[MIT](https://opensource.org/licenses/MIT)
