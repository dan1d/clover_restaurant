require 'sqlite3'
require 'json'
require 'logger'

module CloverRestaurant
  class StateManager
    def initialize(db_path = 'clover_state.db', logger = nil)
      @logger = logger || CloverRestaurant.config&.logger || Logger.new(STDOUT)
      @config = CloverRestaurant.config # Ensure @config is set to access cache_enabled
      @db_path = db_path
      setup_database
    end

    def setup_database
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true

      # Create tables if they don't exist
      @db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS entity_states (
          entity_type TEXT,
          clover_id TEXT,
          name TEXT,
          data TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(entity_type, clover_id)
        );
      SQL

      @db.execute <<-SQL
        CREATE TABLE IF NOT EXISTS setup_steps (
          step_name TEXT PRIMARY KEY,
          completed BOOLEAN DEFAULT 0,
          completed_at DATETIME,
          data TEXT
        );
      SQL
    end

    def record_entity(type, clover_id, name, data = {})
      @db.execute(
        "INSERT OR REPLACE INTO entity_states (entity_type, clover_id, name, data) VALUES (?, ?, ?, ?)",
        [type, clover_id, name, data.to_json]
      )
    end

    def entity_exists?(type, identifier, field = 'name')
      result = @db.get_first_value(
        "SELECT clover_id FROM entity_states WHERE entity_type = ? AND (clover_id = ? OR name = ?)",
        [type, identifier, identifier]
      )
      !result.nil?
    end

    def get_entities(type)
      @db.execute(
        "SELECT * FROM entity_states WHERE entity_type = ? ORDER BY created_at",
        [type]
      ).map do |row|
        row["data"] = JSON.parse(row["data"]) if row["data"]
        row
      end
    end

    def mark_step_completed(step_name, data = {})
      unless @config.cache_enabled
        @logger.info "CACHE DISABLED (config): Skipping mark_step_completed for key: '#{step_name}'"
        return
      end
      @logger.info "CACHE_WRITE: Marking step completed (caching response) for key: '#{step_name}'"
      @db.transaction do
        @db.execute(
          "INSERT OR REPLACE INTO setup_steps (step_name, completed, completed_at, data) VALUES (?, 1, CURRENT_TIMESTAMP, ?)",
          [step_name, data.to_json]
        )
      end
    end

    def step_completed?(step_name)
      unless @config.cache_enabled
        @logger.info "CACHE DISABLED (config): step_completed? returning false for key: '#{step_name}'"
        return false
      end
      result = @db.get_first_value(
        "SELECT completed FROM setup_steps WHERE step_name = ?",
        [step_name]
      )
      result == 1
    end

    def get_step_data(step_name)
      unless @config.cache_enabled
        @logger.info "CACHE DISABLED (config): get_step_data returning nil for key: '#{step_name}'"
        return nil
      end
      @logger.info "CACHE_READ_ATTEMPT: Attempting to read cache for key: '#{step_name}'"
      result = @db.get_first_row(
        "SELECT data FROM setup_steps WHERE step_name = ? AND completed = 1",
        [step_name]
      )
      if result
        @logger.info "CACHE_READ_HIT: Found data for key: '#{step_name}'"
        JSON.parse(result["data"])
      else
        @logger.info "CACHE_READ_MISS: No data found for key: '#{step_name}'"
        nil
      end
    end

    def reset_step(step_name)
      @logger.info "CACHE_DELETE_ATTEMPT: Attempting to delete cache for key: '#{step_name}'"
      @db.transaction do
        @db.execute(
          "DELETE FROM setup_steps WHERE step_name = ?",
          [step_name]
        )
      end
      # Verify deletion
      check = @db.get_first_value("SELECT COUNT(*) FROM setup_steps WHERE step_name = ?", [step_name])
      @logger.info "CACHE_DELETE_VERIFY: Rows remaining for key '#{step_name}': #{check}"
    end

    def reset_all
      @logger.info "CACHE_RESET_ALL: Resetting all steps (deleting all from setup_steps table)."
      @db.transaction do
        @db.execute("DELETE FROM setup_steps")
      end
      # Verify (optional)
      # count = @db.get_first_value("SELECT COUNT(*) FROM setup_steps")
      # @logger.info "CACHE_RESET_ALL_VERIFY: Total rows remaining: #{count}"
    end

    def get_creation_summary
      summary = {}
      @db.execute("SELECT entity_type, COUNT(*) as count FROM entity_states GROUP BY entity_type").each do |row|
        summary[row["entity_type"]] = row["count"]
      end
      summary
    end

    # Added to clear cache entries for a given URL path, typically after a mutation (POST/PUT/DELETE)
    def clear_cache_for_url_path(url_path)
      sanitized_url_path = url_path.gsub(%r{[^a-zA-Z0-9_/.-]}, '_')
      like_pattern = "GET_#{sanitized_url_path}_%"
      @logger.info "CACHE_INVALIDATION_ATTEMPT: URL Path: '#{url_path}', Sanitized: '#{sanitized_url_path}', LIKE pattern: '#{like_pattern}'"

      keys_to_delete = @db.execute("SELECT step_name FROM setup_steps WHERE step_name LIKE ?", [like_pattern]).map { |row| row['step_name'] }

      if keys_to_delete.any?
        @logger.info "CACHE INVALIDATION: Clearing #{keys_to_delete.size} cache entries for URL path '#{url_path}' (pattern: '#{like_pattern}')"
        keys_to_delete.each do |key|
          @logger.info "CACHE INVALIDATION: Deleting key: #{key}"
          reset_step(key)
        end
      else
        @logger.info "CACHE INVALIDATION: No cache entries found for URL path '#{url_path}' (pattern: '#{like_pattern}')"
      end
    end
  end
end
