# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_04_000001) do
  create_table "rbrun_claude_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "git_diff"
    t.integer "sandbox_id", null: false
    t.string "session_uuid", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["sandbox_id"], name: "index_rbrun_claude_sessions_on_sandbox_id"
    t.index ["session_uuid"], name: "index_rbrun_claude_sessions_on_session_uuid", unique: true
  end

  create_table "rbrun_command_executions", force: :cascade do |t|
    t.string "category"
    t.integer "claude_session_id"
    t.text "command", null: false
    t.string "container_id"
    t.datetime "created_at", null: false
    t.bigint "executable_id"
    t.string "executable_type"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.string "image"
    t.string "kind", default: "exec", null: false
    t.integer "port"
    t.boolean "public", default: false
    t.integer "sandbox_id"
    t.datetime "started_at"
    t.string "tag"
    t.datetime "updated_at", null: false
    t.index ["claude_session_id"], name: "index_rbrun_command_executions_on_claude_session_id"
    t.index ["executable_type", "executable_id"], name: "index_command_executions_on_executable"
    t.index ["kind"], name: "index_rbrun_command_executions_on_kind"
    t.index ["sandbox_id"], name: "index_rbrun_command_executions_on_sandbox_id"
    t.index ["tag"], name: "index_rbrun_command_executions_on_tag"
  end

  create_table "rbrun_command_logs", force: :cascade do |t|
    t.integer "command_execution_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "line_number", null: false
    t.string "stream", null: false
    t.datetime "updated_at", null: false
    t.index ["command_execution_id", "stream", "line_number"], name: "idx_rbrun_logs_unique_line", unique: true
    t.index ["command_execution_id"], name: "index_rbrun_command_logs_on_command_execution_id"
  end

  create_table "rbrun_releases", force: :cascade do |t|
    t.string "branch", default: "main", null: false
    t.datetime "created_at", null: false
    t.datetime "deployed_at"
    t.string "environment", default: "production", null: false
    t.text "last_error"
    t.string "ref"
    t.string "registry_tag"
    t.string "server_id"
    t.string "server_ip"
    t.text "ssh_private_key"
    t.text "ssh_public_key"
    t.string "state", default: "pending", null: false
    t.string "tunnel_id"
    t.datetime "updated_at", null: false
    t.index ["environment"], name: "index_rbrun_releases_on_environment"
    t.index ["state"], name: "index_rbrun_releases_on_state"
  end

  create_table "rbrun_sandbox_envs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "sandbox_id", null: false
    t.boolean "secret", default: false, null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["sandbox_id", "key"], name: "index_rbrun_sandbox_envs_on_sandbox_id_and_key", unique: true
    t.index ["sandbox_id"], name: "index_rbrun_sandbox_envs_on_sandbox_id"
  end

  create_table "rbrun_sandboxes", force: :cascade do |t|
    t.string "access_token"
    t.datetime "created_at", null: false
    t.text "docker_compose"
    t.text "env"
    t.boolean "exposed", default: false, null: false
    t.text "last_error"
    t.text "setup"
    t.string "slug"
    t.text "ssh_private_key"
    t.text "ssh_public_key"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_rbrun_sandboxes_on_access_token", unique: true
    t.index ["slug"], name: "index_rbrun_sandboxes_on_slug", unique: true
  end

  add_foreign_key "rbrun_claude_sessions", "rbrun_sandboxes", column: "sandbox_id"
  add_foreign_key "rbrun_command_executions", "rbrun_claude_sessions", column: "claude_session_id"
  add_foreign_key "rbrun_command_logs", "rbrun_command_executions", column: "command_execution_id"
  add_foreign_key "rbrun_sandbox_envs", "rbrun_sandboxes", column: "sandbox_id"
end
