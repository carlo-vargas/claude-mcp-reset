#!/usr/bin/env bats

setup() {
    # Isolate home and project directories for test execution
    export HOME="$BATS_TEST_TMPDIR/fake_home"
    export TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/fake_project"
    export SCRIPT_PATH="$BATS_TEST_DIRNAME/../mcp-reset.sh"

    mkdir -p "$HOME/.claude" "$TEST_PROJECT_DIR/.claude"
    cd "$TEST_PROJECT_DIR" || exit 1
}

# --- Helper Functions ---

# Copies a JSON file and dynamically replaces the project path placeholder safely
prepare_json_template() {
    local source_file="$1"
    local dest_file="$2"

    # Simple, portable cross-platform replacement using native Bash text streaming
    local content=$(<"$source_file")
    echo "${content//PROJECT_PLACEHOLDER/$TEST_PROJECT_DIR}" > "$dest_file"
}

# Extracts the raw JSON payload from an explicitly passed text string argument
extract_json_payload() {
    local raw_text="$1"
    # Extract everything between the first '{' and the last '}'
    local json_payload="{${raw_text#*\{}"
    echo "${json_payload%\}*}"}
}

# --- Test Cases ---

@test "Scenario 1: No configuration or settings files present" {
    run bash "$SCRIPT_PATH" extra_arg_1
    [ "$status" -eq 0 ] || false

    # Verify output falls back to a clean, empty structure
    [[ "$output" == *"--strict-mcp-config --mcp-config {\"mcpServers\":{},\"disabledMcpServers\":[]} extra_arg_1"* ]] || false
}

@test "Scenario 2: Global .claude.json only (No project files or denylists)" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    [ "$status" -eq 0 ] || false

    # Verify baseline formatting wrapper remains valid
    [[ "$output" == *"--strict-mcp-config --mcp-config "*" extra_arg_1"* ]] || false

    local json_payload=$(extract_json_payload "$output")

    # Verify all expected global/project-mapped servers are merged in
    local count=$(jq '.mcpServers | length' <<< "$json_payload")
    [ "$count" -eq 4 ] || false

    run jq -e '.mcpServers."remote-notion-wiki".type == "http"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."internal-company-api".type == "sse"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."local-filesystem".type == "stdio"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."fetch-ftp".command == "uvx"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    # Verify mcps are disabled
    run jq -e '.disabledMcpServers | contains(["remote-notion-wiki","internal-company-api","local-filesystem","fetch-ftp"])' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false
}

@test "Scenario 3: Global .claude.json combined with localized .mcp.json overrides" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"
    cp "$BATS_TEST_DIRNAME/templates/.mcp.json" "$TEST_PROJECT_DIR/.mcp.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    [ "$status" -eq 0 ] || false

   # Verify baseline formatting wrapper remains valid
    [[ "$output" == *"--strict-mcp-config --mcp-config "*" extra_arg_1"* ]] || false

    local json_payload=$(extract_json_payload "$output")

    # Verify new parameters/ports from the local .mcp.json injected cleanly
    local count=$(jq '.mcpServers | length' <<< "$json_payload")
    [ "$count" -eq 5 ] || false

    run jq -e '.mcpServers."python-git-server".command == "uvx"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."internal-company-api".url == "http://localhost:8000/events"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    # Verify remaining inherited root/project properties persist
    run jq -e '.mcpServers."remote-notion-wiki".type == "http"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."local-filesystem".type == "stdio"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    run jq -e '.mcpServers."fetch-ftp".command == "uvx"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    # Verify mcps are disabled
    run jq -e '.disabledMcpServers | contains (["remote-notion-wiki","internal-company-api","local-filesystem","fetch-ftp", "python-git-server"])' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false
}

@test "Scenario 4: Multi-tier configs with user, project, and local denylists active" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"
    cp "$BATS_TEST_DIRNAME/templates/.mcp.json" "$TEST_PROJECT_DIR/.mcp.json"

    # Inject various layers of settings.json files containing deniedMcpServers arrays
    cp "$BATS_TEST_DIRNAME/templates/user-settings.json" "$HOME/.claude/settings.json"
    cp "$BATS_TEST_DIRNAME/templates/project-settings.json" "$TEST_PROJECT_DIR/.claude/settings.json"
    cp "$BATS_TEST_DIRNAME/templates/local-settings.json" "$TEST_PROJECT_DIR/.claude/settings.local.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    [ "$status" -eq 0 ] || false

   # Verify baseline formatting wrapper remains valid
    [[ "$output" == *"--strict-mcp-config --mcp-config "*" extra_arg_1"* ]] || false

    local json_payload=$(extract_json_payload "$output")

    # Only 'local-filesystem' should survive the multi-tier filtering logic
    local count=$(jq '.mcpServers | length' <<< "$json_payload")
    [ "$count" -eq 1 ] || false

    run jq -e '.mcpServers."local-filesystem".type == "stdio"' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false

    # Verify mcps are disabled
    run jq -e '.disabledMcpServers == ["local-filesystem"]' >/dev/null 2>&1 <<< "$json_payload"
    [ "$status" -eq 0 ] || false
}
