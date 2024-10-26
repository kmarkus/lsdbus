#!/bin/bash

# Run the tests for the Lua version specified in LUA_VERSION
# This will

# Set defaults for LUA_VERSION and REPEAT
LUA_VERSION="${LUA_VERSION:-5.4}"

# Check if the specified Lua version binary exists
if ! command -v lua${LUA_VERSION} &> /dev/null; then
  echo "error: Lua version lua${LUA_VERSION} is not installed or not in PATH."
  exit 1
fi

# Start the peer test server in the background and save its PID
echo 'Launching peer test server...'
lua test/peer-testserver.lua > peer-testserver.log 2>&1 &
PEER_SERVER_PID=$!

# Set up a trap to stop the peer test server when the script exits
cleanup() {
    echo "Stopping peer test server with PID " $PEER_SERVER_PID
    kill $PEER_SERVER_PID 2>/dev/null
    wait $PEER_SERVER_PID 2>/dev/null
}
trap cleanup EXIT

# Wait briefly to ensure the peer test server initializes
sleep 0.1

if ! kill -0 $PEER_SERVER_PID 2>/dev/null; then
    echo "error: peer-testserver failed to start. peer-testserver.log follows:"
    cat peer-testserver.log
    exit 1
fi

# Run the tests
echo "running tests with Lua ${LUA_VERSION}, luaunit args " "$@"
pushd test/ &> /dev/null
lua${LUA_VERSION} run.lua "$@"
TEST_EXIT_CODE=$?
popd &> /dev/null

echo "tests completed with exit code " $TEST_EXIT_CODE

# if the exit code is not 0, print the log
if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo 'printing peer-testserver log...'
    cat peer-testserver.log
fi


# Exit with the test script's exit code
exit $TEST_EXIT_CODE
