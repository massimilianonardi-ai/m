NAME
    pkg-state.lib.sh - internal package state-area materialization

DESCRIPTION
    Internal implementation of package mutable-state path validation,
    directory and link creation, journal bookkeeping, and rollback.
    It uses the state-path command instead of inventing a second state model.

FUNCTIONS
    No public functions. Every function in this library is internal and
    begins with an underscore. Consumers must use public package operations
    and must not call these helpers directly.

DEPENDENCIES
    state-path, pkg integration runtime.

SEE ALSO
    pkg-integration.lib.sh
    state-path
