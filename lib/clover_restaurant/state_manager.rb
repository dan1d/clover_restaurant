require 'sqlite3'
require 'json'
require 'logger'

module CloverRestaurant
  class StateManager
    def initialize(db_path = 'clover_state.db')
      @logger = Logger.new(STDOUT)
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
      @db.execute(
        "INSERT OR REPLACE INTO setup_steps (step_name, completed, completed_at, data) VALUES (?, 1, CURRENT_TIMESTAMP, ?)",
        [step_name, data.to_json]
      )
    end

    def step_completed?(step_name)
      result = @db.get_first_value(
        "SELECT completed FROM setup_steps WHERE step_name = ?",
        [step_name]
      )
      result == 1
    end

    def get_step_data(step_name)
      result = @db.get_first_row(
        "SELECT data FROM setup_steps WHERE step_name = ?",
        [step_name]
      )
      result ? JSON.parse(result["data"]) : nil
    end

    def reset_step(step_name)
      @db.execute(
        "DELETE FROM setup_steps WHERE step_name = ?",
        [step_name]
      )
    end

    def reset_all
      @db.execute("DELETE FROM entity_states")
      @db.execute("DELETE FROM setup_steps")
    end

    def get_creation_summary
      summary = {}
      @db.execute("SELECT entity_type, COUNT(*) as count FROM entity_states GROUP BY entity_type").each do |row|
        summary[row["entity_type"]] = row["count"]
      end
      summary
    end
  end
end
