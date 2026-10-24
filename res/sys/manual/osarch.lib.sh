NAME
    osarch.lib.sh - detect and expose the current host OS/architecture identity

DESCRIPTION
    osarch.lib.sh is a sys-owned POSIX sh library that performs host
    OS/architecture detection when it is sourced.

    Source it from an m-integrated shell environment:

        loadsyslib "osarch"

    The library exposes no public callable functions.

    On successful sourcing it determines the host operating system and machine
    architecture with POSIX uname, normalizes known values, constructs the
    combined OS/architecture identity, then exports all three resulting
    variables as readonly shell variables.

PUBLIC STATE
    m_OSARCH_OS
        Normalized operating-system identity.

        Known uname -s values are normalized as follows:

            Linux                 -> linux
            Darwin                -> macos
            MINGW*, MSYS*, CYGWIN* -> windows

        Other values are preserved unchanged.

    m_OSARCH_ARCH
        Normalized machine-architecture identity.

        Known uname -m values are normalized as follows:

            arm64
            aarch64
            ARM64
            AARCH64               -> arm64

            x86_64
            x64
            amd64
            AMD64
            X86_64
            X64                   -> x86_64

        Other values are preserved unchanged.

    m_OSARCH
        Combined identity:

            <m_OSARCH_OS>-<m_OSARCH_ARCH>

SOURCE-TIME BEHAVIOR
    Sourcing the library runs:

        uname -s
        uname -m

    through the POSIX command-search environment.

    If either detection command fails, the library invokes the runtime fatal
    diagnostic for osarch detection failure and does not complete normal
    initialization.

    After successful detection the library exports and marks readonly:

        m_OSARCH_OS
        m_OSARCH_ARCH
        m_OSARCH

    Callers must therefore treat these values as immutable process state after
    the library has been sourced.

FUNCTIONS
    This library exposes no public callable functions.

CALLER OBLIGATIONS
    Source the library only in an m-integrated environment that provides the
    runtime fatal facility.

    Do not attempt to assign to or unset m_OSARCH_OS, m_OSARCH_ARCH or
    m_OSARCH after successful initialization.

    Do not assume that every successfully detected host identity is one of the
    platform values accepted by higher-level consumers. Unknown uname values
    are deliberately preserved by this detection library; consumers that
    require a restricted supported set must validate m_OSARCH themselves.

DEPENDENCIES
    POSIX uname is required through the command -p utility search path.

SEE ALSO
    osarch
    manual
