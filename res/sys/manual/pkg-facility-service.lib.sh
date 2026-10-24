NAME
    pkg-facility-service.lib.sh - internal service facility-part conformance handler

DESCRIPTION
    pkg-facility-service.lib.sh implements trusted internal validation semantics for
    the service typed facility part.

    The baseline service contract requires exactly:

        start   = package-command
        process = foreground
        stop    = sigterm

    A provider realization exists at facility-service/<facility>/start and contains
    one ordinary command name from the same provider package definition. Validation
    proves the declarative mapping and mechanically checkable target properties.

    The handler does not select providers, start or stop processes, create facility
    defaults/bindings, or apply runtime state. Portable process lifecycle remains
    owned by srv.

    Static validation cannot prove that an external process really remains
    foreground or obeys SIGTERM correctly. Those behavioral conformance properties
    require real provider/service validation.

FUNCTIONS
    This library exposes no public callable functions.

SEE ALSO
    pkg-facility.lib.sh
    srv
