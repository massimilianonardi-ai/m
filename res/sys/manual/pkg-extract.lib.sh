NAME
    pkg-extract.lib.sh - normalize package artifacts using catalog range metadata

DESCRIPTION
    pkg-extract.lib.sh materializes one verified package artifact into an
    existing empty caller-supplied staging directory. Physical extraction is
    delegated exclusively to extract. The library owns package-specific
    interpretation of range metadata and useful-root normalization.

    Ordinary package formats call extract once using the range format. flat-pkg
    calls extract with physical format pkg and then selects the catalog component
    Payload. dmg-pkg calls extract with physical format dmg, selects the single
    top-level installer package, calls extract again with physical format pkg,
    then applies component, payload-root and optional overlay metadata.

    After package-specific selection, the useful root is normalized by removing
    chains of single real wrapper directories while preserving a valid macOS
    application-bundle boundary.

FUNCTIONS
    pkg_extract <artifact> <range-dir> <staging-dir>
        Materialize one verified package artifact into the existing empty
        <staging-dir> using metadata from <range-dir>.

        <range-dir> must contain format.

        component is required for flat-pkg and dmg-pkg. payload-root is optional
        for those two formats. overlay is forbidden for flat-pkg and optional
        for dmg-pkg.

        For ordinary formats component, payload-root and overlay are invalid.

        flat-pkg selects the named component Payload from the raw pkg expansion.
        dmg-pkg requires exactly one top-level flat installer package in the raw
        DMG result, selects the named primary component Payload and may apply
        additional overlay components. payload-root and overlay target-root
        values are validated relative paths; overlay destination collisions are
        rejected.

        Installer scripts are never executed.

        Returns 0 on success, 1 for extraction, metadata or normalization failure,
        and 2 for invalid invocation, unsupported format or invalid
        format-specific metadata syntax.

DEPENDENCIES
    readpathce
    extract

SEE ALSO
    extract
    pkg-install.lib.sh
