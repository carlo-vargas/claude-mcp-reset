#!/usr/bin/env bats

setup() {
    export HOME="$BATS_TEST_TMPDIR/fake_home"
    export TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/fake_project"
    export SCRIPT_PATH="$BATS_TEST_DIRNAME/../mcp-fresh.sh"

    mkdir -p "$HOME/.claude"
    mkdir -p "$TEST_PROJECT_DIR/.claude"
    cd "$TEST_PROJECT_DIR"
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

assert_success() {
    [ "$status" -eq 0 ] || false
}

# --- Test Cases ---

@test "Scenario 1: No configuration or settings files present" {
    run bash "$SCRIPT_PATH" extra_arg_1
    assert_success

    # Verify output falls back to a clean, empty structure
    [[ "$output" == *"config {\"mcpServers\":{}} extra_arg_1"* ]]
}

@test "Scenario 2: Global .claude.json only (No project files or denylists)" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    assert_success

    # Verify baseline formatting wrapper remains valid
    [[ "$output" == *"config {\"mcpServers\":"*"}} extra_arg_1"* ]] || false

    # Verify all expected global/project-mapped servers are merged in
    [[ "$output" == *"remote-notion-wiki"* ]] || false
    [[ "$output" == *"internal-company-api"*"sse"* ]] || false
    [[ "$output" == *"local-filesystem"* ]] || false
    [[ "$output" == *"fetch-ftp"* ]] || false

    # Verify filtered/out-of-scope elements are strictly absent
    [[ ! "$output" == *"streamable-http"* ]] || false
    [[ ! "$output" == *"fetch-webpage"* ]]
}

@test "Scenario 3: Global .claude.json combined with localized .mcp.json overrides" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"
    cp "$BATS_TEST_DIRNAME/templates/.mcp.json" "$TEST_PROJECT_DIR/.mcp.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    assert_success

    # Verify new parameters/ports from the local .mcp.json injected cleanly
    [[ "$output" == *"python-git-server"* ]] || false
    [[ "$output" == *"internal-company-api"*"sse"*"8000"* ]] || false

    # Verify remaining inherited root/project properties persist
    [[ "$output" == *"remote-notion-wiki"* ]] || false
    [[ "$output" == *"local-filesystem"* ]] || false
    [[ "$output" == *"fetch-ftp"* ]] || false

    # Verify blocked/out-of-scope settings are skipped
    [[ ! "$output" == *"streamable-http"* ]] || false
    [[ ! "$output" == *"3000"* ]] || false
    [[ ! "$output" == *"fetch-webpage"* ]]
}

@test "Scenario 4: Multi-tier configs with user, project, and local denylists active" {
    prepare_json_template "$BATS_TEST_DIRNAME/templates/.claude.json" "$HOME/.claude.json"
    cp "$BATS_TEST_DIRNAME/templates/.mcp.json" "$TEST_PROJECT_DIR/.mcp.json"

    # Inject various layers of settings.json files containing deniedMcpServers arrays
    cp "$BATS_TEST_DIRNAME/templates/user-settings.json" "$HOME/.claude/settings.json"
    cp "$BATS_TEST_DIRNAME/templates/project-settings.json" "$TEST_PROJECT_DIR/.claude/settings.json"
    cp "$BATS_TEST_DIRNAME/templates/local-settings.json" "$TEST_PROJECT_DIR/.claude/settings.local.json"

    run bash "$SCRIPT_PATH" extra_arg_1
    assert_success

    # Only 'local-filesystem' should survive the multi-tier filtering logic
    [[ "$output" == *"local-filesystem"* ]] || false

    # Explicitly confirm all banned servers were cleanly stripped by your script
    [[ ! "$output" == *"remote-notion-wiki"* ]] || false
    [[ ! "$output" == *"internal-company-api"* ]] || false
    [[ ! "$output" == *"fetch-ftp"* ]]
    [[ ! "$output" == *"python-git-server"* ]] || false

    # Other that must not be included but mentioned in configuration or setting files
    [[ ! "$output" == *"fetch-webpage"* ]] || false
    [[ ! "$output" == *"other-mcp"* ]] || false
}
