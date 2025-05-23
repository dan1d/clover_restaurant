## Project: clover_restaurant

This project simulates a restaurant using a Ruby-based system. It involves managing employees, roles, and potentially other restaurant-related entities.

### Key Components & Discoveries:

*   **`simulate_restaurant.rb`**: A script used to run simulations. It interacts with the `StateManager` and `EmployeeService`. It can be run with a `--reset` flag, likely to clear and repopulate data.
*   **`EmployeeService` (`employee_service.rb`)**: Contains logic for managing employees, including creating random employees.
    *   The method `create_random_employees` initially had a bug where it expected `roles` to be a hash with an "elements" key, but it was actually receiving an array of role data hashes.
    *   The problematic line was `return [] unless roles && roles["elements"]` and `available_roles = roles["elements"]`.
    *   The fix involved changing this to `return [] if roles.nil? || !roles.is_a?(Array) || roles.empty?` and `available_roles = roles`. This correctly handles the array of roles passed from the `StateManager`.
*   **`StateManager`**: Manages the state of entities in the simulation.
    *   `@state.get_entities('role')` returns an array of database row hashes, e.g., `[{"entity_type"=>"role", "data"=>{actual_role_hash}}, ...]`.
*   **Gem Management**: The project is packaged as a Ruby gem (`clover_restaurant.gemspec`). The typical workflow involves:
    1.  `gem uninstall clover_restaurant -x --force`
    2.  `gem build clover_restaurant.gemspec`
    3.  `gem install ./clover_restaurant-0.1.0.gem` (version might change)
*   **Error Encountered**: `no implicit conversion of String into Integer` in `employee_service.rb`. This was caused by attempting to access an array with a string key (e.g., `array["elements"]`).

### Debugging Process:

1.  Initial run of `./simulate_restaurant.rb --reset` failed with "no such file or directory."
    *   Resolved by changing to the `clover_restaurant` directory.
2.  Subsequent run failed with `no implicit conversion of String into Integer` at `employee_service.rb:385`.
3.  Investigated `employee_service.rb` and `simulate_restaurant.rb`.
4.  Identified the error line in `create_random_employees`.
5.  Hypothesized that `roles` was a String, but `simulate_restaurant.rb` passes `get_entities('role')` which returns an array.
6.  Added logging to `create_random_employees` to inspect the `roles` parameter.
7.  Rebuilt and reinstalled the gem.
8.  Logs confirmed `roles` was an array of hashes as expected. The error `array["elements"]` was indeed the cause.
9.  Corrected the logic in `create_random_employees` to handle the array of roles directly.
10. Uninstalled, built, and installed the gem again.
11. Awaiting results of running `./simulate_restaurant.rb --reset` with the fix.

### Purpose of this File:

This file (`AI.MD`) serves as a knowledge base for an AI assistant to quickly understand the context, history, and key components of the `clover_restaurant` project when a new chat session is initiated.
