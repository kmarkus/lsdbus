#!/bin/bash

# Run the tests for the Lua version specified in LUA_VERSION

# Set defaults for LUA_VERSION and REPEAT
LUA_VERSION="${LUA_VERSION:-5.4}"

# Check if the specified Lua version binary exists
if ! command -v lua${LUA_VERSION} &> /dev/null; then
  echo "error: Lua version lua${LUA_VERSION} is not installed or not in PATH."
  exit 1
fi

# Unique log file per run so failed runs can be examined later
LOG_FILE="peer-testserver-${LUA_VERSION}-$(date +%Y%m%d-%H%M%S)-$$.log"

# Start the peer test server in the background and save its PID
echo 'Launching peer test server...'
lua${LUA_VERSION} test/peer-testserver.lua > "$LOG_FILE" 2>&1 &
PEER_SERVER_PID=$!

# Set up a trap to stop the peer test server when the script exits
cleanup() {
    kill $PEER_SERVER_PID 2>/dev/null
    wait $PEER_SERVER_PID 2>/dev/null
}
trap cleanup EXIT

# Wait briefly to ensure the peer test server initializes
sleep 0.1

if ! kill -0 $PEER_SERVER_PID 2>/dev/null; then
    echo "error: peer-testserver failed to start. Log: $LOG_FILE"
    cat "$LOG_FILE"
    exit 1
fi

# Run the tests
echo "running tests with Lua ${LUA_VERSION}, luaunit args " "$@"
pushd test/ &> /dev/null
lua${LUA_VERSION} run.lua "$@"
TEST_EXIT_CODE=$?
popd &> /dev/null

if [ $TEST_EXIT_CODE -ne 0 ]; then
    printf '\033[31mFAIL\033[0m  peer-testserver log: %s\n' "$LOG_FILE"
else
    rm -f "$LOG_FILE"
fi

exit $TEST_EXIT_CODE
