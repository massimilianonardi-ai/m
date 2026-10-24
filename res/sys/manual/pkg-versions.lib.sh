NAME
    pkg-versions.lib.sh - report installed package concrete identities

DESCRIPTION
    Package-subcommand library loaded by the public pkg command.

FUNCTIONS
    pkg_versions <package-request>
        Print the installed concrete names for the selected package class,
        one per line. The package request must designate a package and may
        select a platform class, but cannot request one exact version.
        Returns nonzero for invalid requests or unavailable classes.

DEPENDENCIES
    pkg-local.lib.sh, m_PKG_DIR.

SEE ALSO
    pkg
    pkg-local.lib.sh
