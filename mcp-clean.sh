#!/bin/bash

# --- Check Dependencies ---
if ! command -v jq &> /dev/null; then
  echo "ERROR: 'jq' utility is required but not installed. Terminating script." >&2
  exit 1
fi

# --- Configuration Paths ---
GLOBAL_CONFIG="$HOME/.claude.json"
LOCAL_CONFIG="./.mcp.json"
CURRENT_DIR=$PWD

GLOBAL_SETTING="$HOME/.claude/settings.json"
PROJECT_SETTING="./.claude/settings.json"
LOCAL_SETTING="./.claude/settings.local.json"

# --- Extract MCP Servers ---
[ -f "$GLOBAL_CONFIG" ] && USER_MCP=$(jq -c '.mcpServers // {}' "$GLOBAL_CONFIG" 2>/dev/null) || USER_MCP='{}'
[ -f "$GLOBAL_CONFIG" ] && LOCAL_MCP=$(jq -c --arg d "$CURRENT_DIR" '.projects[$d].mcpServers // {}' "$GLOBAL_CONFIG" 2>/dev/null) || LOCAL_MCP='{}'
[ -f "$LOCAL_CONFIG" ] && PROJECT_MCP=$(jq -c '.mcpServers // {}' "$LOCAL_CONFIG" 2>/dev/null) || PROJECT_MCP='{}'

# --- Extract Denied Servers ---
DENIED_MCP_GLOBAL=$( [ -f "$GLOBAL_SETTING" ] && jq -c '.deniedMcpServers // []' "$GLOBAL_SETTING" 2>/dev/null || echo '[]' )
DENIED_MCP_PROJECT=$( [ -f "$PROJECT_SETTING" ] && jq -c '.deniedMcpServers // []' "$PROJECT_SETTING" 2>/dev/null || echo '[]' )
DENIED_MCP_LOCAL=$( [ -f "$LOCAL_SETTING" ] && jq -c '.deniedMcpServers // []' "$LOCAL_SETTING" 2>/dev/null || echo '[]' )

ALL_MCP=$(jq -c -n \
  --argjson userMcp "$USER_MCP" \
  --argjson localMcp "$LOCAL_MCP" \
  --argjson projectMcp "$PROJECT_MCP" \
  '$userMcp + $localMcp + $projectMcp'
)

ALL_DENIED_MCP=$(jq -c -n \
  --argjson dg "$DENIED_MCP_GLOBAL" \
  --argjson dp "$DENIED_MCP_PROJECT" \
  --argjson dl "$DENIED_MCP_LOCAL" \
  '$dg + $dp + $dl'
)

FILTERED=$(jq -c -n \
  --argjson s "$ALL_MCP" \
  --argjson d "$ALL_DENIED_MCP" \
  '($d | unique) as $b | { mcpServers: ($s | with_entries(select([.key] | inside($b) | not))) }'
)

if [ -n "$BATS_TEST_TMPDIR" ]; then
  echo "MOCK_EXEC: claude --strict-mcp-config --mcp-config $FILTERED $*"
  exit 0
fi

exec claude --strict-mcp-config --mcp-config "$FILTERED" "$@"

