NAME
    pkg-facility-cmd.lib.sh - internal cmd facility-part conformance handler

DESCRIPTION
    pkg-facility-cmd.lib.sh implements the trusted internal validation semantics for
    the cmd typed facility part. A provider command realization may name either an
    executable contained by the provider useful root or one validated ordinary
    package command of the same provider through the
    package-command<TAB><command> descriptor form. Same-provider package-command
    delegation validates the package command definition/link against that provider's
    useful root and never authorizes unrelated PATH resolution. Exact contract
    membership is then composed with realization validation for provider
    conformance. Package integration reuses the same internal realization
    validation without acquiring catalog context.

    The library performs no command publication or provider selection.

FUNCTIONS
    This library exposes no public callable functions.

SEE ALSO
    pkg-facility.lib.sh
