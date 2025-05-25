# --- AI.md Maintenance Protocol ---

## Guidelines for AI Assistants Updating This Document

**Purpose:**
These guidelines are for AI assistants to ensure that this `AI.MD` document remains an accurate, up-to-date, and valuable resource for understanding and maintaining the `clover_restaurant` gem, particularly its simulation script and underlying service interactions with the Clover API.

**When to Propose an Update to This Document:**

An update to `AI.MD` should be considered and proposed to the user in the following scenarios:

1.  **Simulator Logic Changes:** After significant modifications to `simulate_restaurant.rb`, such as:
    *   Changes in the order of entity creation.
    *   Addition or removal of entity types being simulated (e.g., new Clover features supported).
    *   Alterations to how data is generated (e.g., new randomization patterns, different default values).
    *   Changes to command-line arguments or their behavior.
2.  **Service Layer Modifications:** When there are notable changes to the service classes (`InventoryService`, `EmployeeService`, etc.) in `lib/clover_restaurant/services/`:
    *   New methods added to interact with different Clover API endpoints.
    *   Significant refactoring of existing service methods.
    *   Changes in how API responses are handled or how data is prepared for Clover.
3.  **Clover API Integration Changes:** If the gem adapts to new versions of the Clover API, or if there are changes in how the gem authenticates or interacts with Clover (e.g., new fields required, different endpoint paths used for core entities).
4.  **Bug Fixes with Architectural Impact:** When a bug fix leads to a noteworthy change in how an entity is created, fetched, or managed (e.g., improved duplicate prevention logic, new ways of handling deleted entities across all services).
5.  **Core Dependency or Workflow Changes:** When critical dependencies change, or the gem development/testing workflow is altered (e.g., changes to `Rakefile` tasks, `gemspec` updates affecting usage, new environment variable requirements).
6.  **Troubleshooting & Gotchas:** When new common issues, their solutions, critical "gotchas," or important debugging insights related to the simulator or gem usage are identified.

**What to Update (Content Guidelines):

*   **Identify Relevant Sections:** Determine which existing sections (e.g., "Key Components & Current State", "Entity Creation Flow", "Recent Fixes & Improvements", "Usage") require modification or if new sections are needed.
*   **Be Concise yet Comprehensive:** Provide enough detail for another developer (human or AI) to understand the change and its implications for the simulator or gem, but avoid unnecessary verbosity.
*   **Focus on Simulator Behavior:** For this project, `AI.MD` should heavily focus on how `simulate_restaurant.rb` works, what it creates, and how to use it.
*   **New Entities/Services:** If new entities are simulated or new services are added, document:
    *   Their purpose in the simulation.
    *   Where they fit in the `Entity Creation Flow`.
    *   Any new service class dependencies.
*   **Refactoring:** If significant refactoring occurred (especially in the services or the main script), briefly explain the "before" (if it helps understanding the improvement) and clearly describe the "after" state.
*   **Code References:** Use backticks for `simulate_restaurant.rb`, `ServiceClassName`, `method_name()`, `lib/path/to/file.rb`, `--command-line-flag`, and environment variables like `CLOVER_API_TOKEN`.

**Style and Formatting:**

*   **Maintain Consistency:** Adhere to the existing Markdown style, formatting, and tone of this document.
*   **Clarity:** Use clear and unambiguous language.

**Self-Correction/Confirmation Prompt for AI:**

> "After applying changes to the `clover_restaurant` codebase (e.g., `simulate_restaurant.rb` or service classes) based on the user's requests, I will review these `AI.MD` Maintenance Protocol guidelines. If the recent work warrants an update to this documentation, I will inform the user and propose the specific changes to `AI.MD` or, if highly confident and the changes are additive and clearly defined, I may apply them directly and then inform the user of the update I made."

## Project: clover_restaurant

This project simulates a restaurant using a Ruby-based system that integrates with the Clover POS API. It creates comprehensive restaurant data including menu items, employees, categories, and more. The primary utility is the `simulate_restaurant.rb` script.

### Major Architecture Update (January 2025):

**SIMPLIFIED APPROACH - STATE MANAGER REMOVED:**
The system was significantly simplified by removing the StateManager complexity. The simulator now always performs a full reset and setup, making it much more reliable and easier to understand.

### Key Components & Simulator Features:

*   **`simulate_restaurant.rb`**: Main script that creates a complete restaurant setup in Clover.
    *   **🔄 Always Resets**: No more state management - always does a clean setup. The script ensures a fresh environment by default, removing the need for a `--reset` flag.
    *   **📊 Comprehensive Entity Setup**: Creates all essential restaurant entities (detailed below).
    *   **💳 Optional Order Generation**: Use the `--generate-orders` flag to create a history of realistic orders with various payment methods, tips, discounts, and proper tax calculations. Orders span multiple days with varied patterns (e.g., busier on weekends).
    *   **🛡️ Fixed Major Issues**: Past problems with duplicate menu items, incorrect handling of deleted entities, and unreliable category associations have been resolved.
    *   **⚙️ Single Command Focus**: Primary usage is just `./simulate_restaurant.rb` for setup, and `./simulate_restaurant.rb --generate-orders` to include order history.

*   **Service Architecture**: Well-organized service classes in `lib/clover_restaurant/services/` for different Clover API endpoints:
    *   `InventoryService`: Manages menu items, categories, modifier groups, and tax rates. Includes logic to prevent duplicate item creation by checking existing items by name.
    *   `EmployeeService`: Handles employees, roles, and shifts.
    *   `CustomerService`: Manages customer creation.
    *   `OrderService`: Responsible for order creation and management, including adding line items, discounts, and notes.
    *   `PaymentService`: Processes payments for orders, including tips and split payments if applicable.
    -   `DiscountService`: Manages creation of various discount types (percentage and fixed amount).
    *   **Note**: All service methods that fetch lists of entities (e.g., `get_categories`, `get_modifiers`) now automatically filter out any entities marked as `deleted: true` by the Clover API, preventing errors related to referencing deleted data.

### Entity Creation Flow & What Gets Created:

The simulator creates a realistic restaurant environment. The typical order of creation is:

1.  **Tax Rates**: e.g., Sales Tax (8.5%), Alcohol Tax (10%).
2.  **Categories**: ~7 categories like Appetizers, Entrees, Sides, Desserts, Drinks, Alcoholic Beverages, Specials.
3.  **Modifier Groups & Modifiers**: ~5 groups like Temperature (Rare, Medium, Well Done), Add-ons (Extra Cheese, Bacon), Sides Choice (Fries, Salad), Salad Dressings (Ranch, Vinaigrette), Drink Size (Small, Large).
4.  **Menu Items**: 21+ realistic items with pricing, descriptions, and correct category/modifier associations. Examples: Bruschetta ($9.95), NY Strip Steak ($32.95), Craft Beer ($6.95). Duplicate checking by name is performed.
5.  **Discounts**: Various percentage (e.g., 10% Off) and fixed-amount (e.g., $5 Off) discounts.
6.  **Employee Roles**: Manager, Server, Bartender, Host, etc., with predefined permissions.
7.  **Employees**: ~15 randomly generated employees, assigned roles, and given PINs.
8.  **Shifts**: Clocks in some employees to create active shift data.
9.  **Customers**: ~30 random customers to associate with historical orders.
10. **Order Types**: Standard types like Dine In, Take Out, Delivery.
11. **(Optional) Orders & Payments**: If `--generate-orders` is used, a history of orders is created with line items, payments, tips, and taxes.

### Recent Fixes & Key Improvements (Consolidated):

*   **State Manager Removal**: Eliminated complex state tracking. The simulator now always creates fresh data, leading to simpler, more predictable, and reliable behavior. This resolved issues related to complex resumption logic.
*   **Deleted Entity Filtering**: Fixed a major bug where the system was trying to use categories/modifiers deleted in previous runs. All `get_*` methods in services now filter out entities where `deleted: true` from the API response, preventing "No category with id XXX" errors and category association failures.
*   **Duplicate Prevention**: Added robust duplicate checking in `InventoryService::ItemCreator` (and similar services) when creating entities like menu items. It checks if an item already exists by name before creating a new one.
*   **Simplified Command Line**: The primary command is now just `./simulate_restaurant.rb`. The `--reset` flag is no longer needed as resetting is the default behavior.
*   **Reliable Setup & Associations**: Menu items are now consistently and correctly linked to non-deleted categories and modifiers.
*   **Error Handling**: Improved error messages and logging throughout the services and the main script to aid in debugging.

### Fixed Issues Summary (Historical):
1.  **"No category with id X" errors**: Resolved by filtering deleted entities.
2.  **Duplicate menu items/other entities**: Resolved by removing state management and adding explicit duplicate checks by name before creation.
3.  **Complex and unreliable resumption logic**: Removed entirely in favor of a full-reset approach.
4.  **Category/modifier association failures**: Resolved by ensuring only active, non-deleted entities are referenced.

### Usage (`simulate_restaurant.rb`):

Ensure you have completed the prerequisites (Ruby, Bundler, `.env` file as specified in `README.md`).

1.  **Make the script executable (if needed):**
    ```bash
    chmod +x simulate_restaurant.rb
    ```
2.  **Basic setup (creates all restaurant entities - menu, staff, etc.):**
    ```bash
    ./simulate_restaurant.rb
    ```
3.  **Setup with historical orders/payments:**
    ```bash
    ./simulate_restaurant.rb --generate-orders
    ```

### Gem Management Workflow (Development):

As outlined in the main `README.md`:
```bash
# After making code changes to the gem (in lib/):
gem build clover_restaurant.gemspec
# Replace 0.1.0 with the actual version generated if it differs
gem install ./clover_restaurant-0.1.0.gem
# Then run the simulator to test
./simulate_restaurant.rb
```

### Environment Setup:

Requires a `.env` file in the project root with:
```env
CLOVER_API_TOKEN=your_sandbox_api_token
CLOVER_MERCHANT_ID=your_merchant_id
# Optional: CLOVER_ENVIRONMENT=https://api.clover.com/ (if targeting production, defaults to sandbox: https://sandbox.dev.clover.com/)
```

### Order Generation Details (when `--generate-orders` is used):
- Creates a set of historical orders, typically spanning several days to simulate realistic activity.
- Order patterns may vary (e.g., simulating busier periods on weekends or specific mealtimes).
- Includes various payment methods (Cash, Credit Card types) and tip amounts.
- Applies both line-item level discounts and order-level discounts randomly.
- Ensures proper tax calculations are applied based on the tax rates set up.
- Associates orders with the randomly generated customers.

### Troubleshooting Common Issues:
- **Permission denied when running `./simulate_restaurant.rb`**:
    - **Fix**: Run `chmod +x simulate_restaurant.rb` to make the script executable.
- **Missing gems / `Bundler::GemNotFound` errors**:
    - **Fix**: Ensure you have run `bundle install` in the project root to install all dependencies listed in the `Gemfile`.
- **Clover API errors (e.g., 401 Unauthorized, 404 Merchant Not Found)**:
    - **Fix**: Double-check your `.env` file. Ensure `CLOVER_API_TOKEN` and `CLOVER_MERCHANT_ID` are correct and have the necessary permissions for your target Clover environment (sandbox or production).
    - **Fix**: Verify `CLOVER_ENVIRONMENT` if set, or ensure you're targeting sandbox if it's not set (default behavior).
- **Duplicate entity errors during simulation (e.g., "Item with name X already exists")**:
    - This class of error should largely be mitigated by the recent architectural changes that always reset and include duplicate checks. If encountered, it might indicate a new scenario or an issue in the duplicate checking logic for a specific entity type that needs investigation.
- **Script stops unexpectedly or throws Ruby errors**:
    - Check the terminal output for specific Ruby error messages and stack traces. This can indicate issues with API response parsing, unexpected `nil` values, or logic errors in one ofthe services.

### Current Status:

✅ **Working**: All entity creation flows are operational.
✅ **Fixed**: Historical issues with duplicate items and incorrect references to deleted entities are resolved.
✅ **Simplified**: The removal of state management has significantly reduced complexity.
✅ **Reliable**: The simulator provides consistent behavior on every run due to the full reset approach.

### Purpose of this File:

This `AI.MD` file serves as the primary knowledge base for AI assistants (and human developers) to quickly understand the current state, architecture, detailed features, entity creation flow, recent changes, and troubleshooting for the `clover_restaurant` project, particularly its `simulate_restaurant.rb` script. The system is now much simpler and more reliable after removing the StateManager complexity and improving entity handling.
