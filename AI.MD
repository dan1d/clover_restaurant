## Project: clover_restaurant

This project simulates a restaurant using a Ruby-based system that integrates with the Clover POS API. It creates comprehensive restaurant data including menu items, employees, categories, and more.

### Major Architecture Update (January 2025):

**SIMPLIFIED APPROACH - STATE MANAGER REMOVED:**
The system was significantly simplified by removing the StateManager complexity. The simulator now always performs a full reset and setup, making it much more reliable and easier to understand.

### Key Components & Current State:

*   **`simulate_restaurant.rb`**: Main script that creates a complete restaurant setup in Clover
    *   **Always resets**: No more state management - always does a clean setup
    *   **Single command**: Just run `./simulate_restaurant.rb` (no --reset flag needed)
    *   **Optional orders**: Use `--generate-orders` flag to create historical orders/payments
    *   **Fixed duplicate issues**: Resolved problems with duplicate menu items and deleted entity references

*   **Service Architecture**: Well-organized service classes for different Clover endpoints:
    *   `InventoryService`: Menu items, categories, modifier groups
    *   `EmployeeService`: Employees, roles, shifts
    *   `CustomerService`: Customer management
    *   `OrderService`: Order creation and management
    *   `PaymentService`: Payment processing
    *   `DiscountService`: Discount management

*   **Entity Creation Flow**:
    1. Tax rates (sales tax, etc.)
    2. Categories (Appetizers, Entrees, Drinks, etc.)
    3. Modifier groups (Temperature, Add-ons, Sides, etc.)
    4. Menu items (with proper category associations)
    5. Discounts (percentage and fixed amount)
    6. Employee roles (Manager, Server, Bartender, etc.)
    7. Employees (15 random employees with roles)
    8. Shifts (clock in employees)
    9. Customers (30 random customers)
    10. Order types (Dine In, Take Out, Delivery)

### Recent Fixes & Improvements:

*   **Deleted Entity Filtering**: Fixed major bug where system was trying to use deleted categories/modifiers
    *   All get_* methods now filter out `deleted: true` entities
    *   Prevents "No category with id XXX" errors
*   **Duplicate Prevention**: Added duplicate checking in item creation
    *   `create_item` method checks if item already exists by name before creating
*   **State Manager Removal**: Eliminated complex state tracking system
    *   Simpler, more predictable behavior
    *   Always creates fresh data
*   **Error Handling**: Improved error messages and logging throughout

### Fixed Issues:

1. **"No category with id" errors**: System was referencing deleted categories from previous runs
2. **Duplicate menu items**: Items were being created multiple times due to state management issues
3. **Complex resumption logic**: Removed in favor of simple full-reset approach
4. **Category association failures**: Fixed by ensuring only non-deleted entities are used

### Usage:

```bash
# Basic setup (creates all entities)
./simulate_restaurant.rb

# Setup + generate historical orders/payments
./simulate_restaurant.rb --generate-orders
```

### Gem Management Workflow:

```bash
# After making code changes:
gem build clover_restaurant.gemspec
gem install ./clover_restaurant-0.1.0.gem
./simulate_restaurant.rb
```

### Environment Setup:

Requires `.env` file with:
```
CLOVER_API_TOKEN=your_sandbox_token
CLOVER_MERCHANT_ID=your_merchant_id
```

### Current Status:

✅ **Working**: All entity creation flows
✅ **Fixed**: Duplicate items and deleted entity references
✅ **Simplified**: No more state management complexity
✅ **Reliable**: Consistent behavior on every run

### Purpose of this File:

This file serves as a knowledge base for AI assistants to quickly understand the current state, recent changes, and architecture of the `clover_restaurant` project. The system is now much simpler and more reliable after removing the StateManager complexity.
