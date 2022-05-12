# API Changes

- `b:add_signal`: takes a numeric signals numbers instead of a
  string. the `lsdbus` module defines constants for supported signals.

- additional parameter for callbacks. The callbacks for `match`,
  `match_signal`, `call_async`, `add_signal`, `add_periodic` and
  `add_io` receive the `bus` object as an additional first
  parameter. This avoids the need to pass the bus (e.g. for
  `b:exit_loop()` via the scope.

  The server method `handler` and property `get` and `set` handlers
  receive the `vtable` table returned from `lsdbus.server:new`. Again
  this avoids the need to pass the `bus` object in via the scope and
  moreover provides a table that can be freely used to store state
  such as property values.
