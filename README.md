# Clover Restaurant Gem & Simulator

This project provides a Ruby gem, `clover_restaurant`, designed to interact with the Clover POS API. It includes a simulator script, `simulate_restaurant.rb`, that creates a comprehensive restaurant setup in your Clover merchant account with realistic data.

## For AI/LLM Assistants

If you are an AI assistant, please refer to the `AI.MD` file in the root of this project. It contains a summary of recent architectural changes, current project state, fixed issues, and debugging history.

## `simulate_restaurant.rb` - Restaurant Environment Simulator

The primary utility of this project is the `simulate_restaurant.rb` script. It creates a complete restaurant environment in your Clover sandbox or development merchant account, perfect for testing integrations, demos, or development.

### 🚀 Recent Major Update (January 2025)

**SIMPLIFIED ARCHITECTURE:** The simulator has been completely simplified by removing the StateManager complexity. It now always performs a clean setup, making it much more reliable and predictable.

### Features of the Simulator:

*   **🔄 Always Resets:** No more state management - always creates fresh data
*   **📊 Comprehensive Setup:** Creates all essential restaurant entities:
    *   **Tax Rates** (Sales Tax, Alcohol Tax, etc.)
    *   **Categories** (Appetizers, Entrees, Sides, Desserts, Drinks, etc.)
    *   **Modifier Groups & Modifiers** (Temperature, Add-ons, Sides Choice, Drink Size, etc.)
    *   **Menu Items** (21+ realistic items with pricing, descriptions, and category assignments)
    *   **Employee Roles** (Manager, Server, Bartender, Host, etc.)
    *   **Employees** (15 randomly generated with roles and PINs)
    *   **Shifts** (Clocks in employees to create active shift data)
    *   **Customers** (30 random customers for order history)
    *   **Order Types** (Dine In, Take Out, Delivery)
    *   **Discounts** (Various percentage and fixed-amount discounts)
*   **💳 Optional Order Generation:** Generate realistic historical orders with payments
*   **🛡️ Fixed Major Issues:**
    *   No more duplicate menu items
    *   Proper handling of deleted entities
    *   Reliable category associations
    *   Consistent behavior on every run

### Prerequisites:

1.  **Ruby Environment:** Ruby 2.7+ recommended
2.  **Bundler:** Install with `gem install bundler`
3.  **Dependencies:** Run `bundle install` in the project root
4.  **Clover API Credentials:** Set up a `.env` file in the project root:
    ```env
    CLOVER_API_TOKEN=your_sandbox_api_token
    CLOVER_MERCHANT_ID=your_merchant_id
    # Optional: CLOVER_ENVIRONMENT=https://api.clover.com/ (defaults to sandbox)
    ```

### How to Run the Simulator:

1.  **Navigate to the project directory:**
    ```bash
    cd clover_restaurant
    ```

2.  **Basic setup (creates all restaurant entities):**
    ```bash
    ./simulate_restaurant.rb
    ```

3.  **Setup with historical orders/payments:**
    ```bash
    ./simulate_restaurant.rb --generate-orders
    ```

4.  **After making code changes, rebuild the gem:**
    ```bash
    gem build clover_restaurant.gemspec
    gem install ./clover_restaurant-0.1.0.gem
    ./simulate_restaurant.rb
    ```

### What Gets Created:

The simulator creates a realistic restaurant environment with:

- **7 Categories:** Appetizers, Entrees, Sides, Desserts, Drinks, Alcoholic Beverages, Specials
- **21+ Menu Items:** Including Bruschetta ($9.95), NY Strip Steak ($32.95), Craft Beer ($6.95), etc.
- **5 Modifier Groups:** Temperature, Add-ons, Sides Choice, Salad Dressings, Drink Size
- **Employee Structure:** Complete staff with different roles and permissions
- **Order History:** (Optional) Realistic past orders with payments, tips, and taxes

### Key Improvements:

✅ **Simplified Command Line:** Just `./simulate_restaurant.rb` (no --reset needed)
✅ **Reliable Setup:** No more complex state management
✅ **Fixed Duplicates:** Each item is created only once
✅ **Proper Associations:** Menu items correctly linked to categories
✅ **Error Prevention:** Filters out deleted entities automatically

### Troubleshooting:

**Common Issues:**
- **Permission denied:** Run `chmod +x simulate_restaurant.rb`
- **Missing gems:** Run `bundle install`
- **API errors:** Check your `.env` file has correct credentials
- **Duplicate errors:** This should no longer happen with the new version

### Order Generation (Optional):

When using `--generate-orders`, the simulator creates:
- Historical orders spanning multiple days
- Realistic order patterns (busier on weekends)
- Various payment methods and tips
- Line item discounts and order-level discounts
- Proper tax calculations

## Gem Development

The `clover_restaurant` gem provides organized service classes for different Clover API endpoints:

- **InventoryService:** Menu management
- **EmployeeService:** Staff and roles
- **CustomerService:** Customer management
- **OrderService:** Order creation and management
- **PaymentService:** Payment processing
- **DiscountService:** Discount management

### Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

### License

[MIT](https://opensource.org/licenses/MIT)
