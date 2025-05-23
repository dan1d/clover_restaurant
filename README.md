# Clover Restaurant Gem & Simulator

This project provides a Ruby gem, `clover_restaurant`, designed to interact with the Clover POS API. It also includes a simulator script, `simulate_restaurant.rb`, to populate a Clover merchant account with a comprehensive set of data for a typical restaurant setup.

## For AI/LLM Assistants

If you are an AI assistant, please refer to the `AI.MD` file in the root of this project. It contains a summary of the project, key components, technologies used, and a log of significant past debugging sessions and architectural decisions. This will help you quickly get up to speed with the project context.

## `simulate_restaurant.rb` - Restaurant Environment Simulator

The primary utility of this project is the `simulate_restaurant.rb` script. Its purpose is to create a full suite of restaurant-related entities in your Clover sandbox or development merchant account. This is extremely useful for testing integrations, demoing features, or quickly setting up a development environment.

### Features of the Simulator:

*   **Resets State:** Can clear previously generated data for a fresh start.
*   **Comprehensive Setup:** Creates essential restaurant entities, including:
    *   Tax Rates (e.g., Sales Tax, Alcohol Tax)
    *   Categories (e.g., Appetizers, Entrees, Drinks)
    *   Modifier Groups & Modifiers (e.g., Temperature, Add-ons, Sides)
    *   Menu Items (with pricing, descriptions, and category assignments)
    *   Employee Roles (e.g., Manager, Server, Bartender)
    *   Employees (randomly generated with roles and PINs)
    *   Shifts (clocks in employees to create shift data)
*   **Idempotent Steps:** If a step has been completed previously (and not reset), the script will skip it, allowing for resumption.
*   **Detailed Logging:** Provides informative output about the setup process.

### Prerequisites:

1.  **Ruby Environment:** Ensure you have Ruby installed.
2.  **Bundler:** Install bundler if you haven't: `gem install bundler`
3.  **Dependencies:** Navigate to the project root and run `bundle install` to install required gems.
4.  **Clover API Credentials:**
    *   Set up a `.env` file in the project root with your Clover API token and merchant ID:
        ```
        CLOVER_API_TOKEN=your_api_token_here
        CLOVER_MERCHANT_ID=your_merchant_id_here
        # Optional: CLOVER_ENVIRONMENT=https://api.clover.com/ (for production, defaults to sandbox)
        ```

### How to Run the Simulator:

1.  Navigate to the `clover_restaurant` directory.
2.  Make sure the script is executable: `chmod +x simulate_restaurant.rb`
3.  Run the script:
    ```bash
    ./simulate_restaurant.rb
    ```
4.  **To reset all previously generated data and start fresh:**
    ```bash
    ./simulate_restaurant.rb --reset
    ```

The script will then proceed to set up all the necessary entities in your specified Clover merchant account.

## Gem Development (clover_restaurant)

The `clover_restaurant` gem provides a suite of services to interact with various Clover API endpoints.

(Information about gem structure, specific service usage, and advanced configuration would go here if the focus was purely on the gem's library usage. For now, the emphasis is on the simulator.)

### Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

### License

[MIT](https://opensource.org/licenses/MIT)
