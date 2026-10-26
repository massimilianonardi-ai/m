NAME
    pkg-repository-chrome.lib.sh - Google Chrome stable Debian repository adapter

DESCRIPTION
    Implements the chrome repository type using Google's official Linux
    stable amd64 Debian Packages index. The repository descriptor contains
    exactly:

        type = chrome

    The adapter reads upstream Package/Version/Architecture/Filename/Size/
    SHA256 records for google-chrome-stable, validates the expected Debian
    package path and SHA-256, and emits canonical artifact descriptors for
    the generic verified package downloader. Unknown descriptor fields,
    malformed records and unavailable exact versions are rejected.

    Package versions use numeric component ordering across four Chrome
    components and one Debian package revision. Version comparison is
    local; exact release resolution requires presence in the current
    upstream package index. This repository type currently applies to
    the catalog's Linux amd64 Chrome package.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print validated versions from the current upstream Packages index
        in ascending numeric package-version order.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 from local numeric Chrome/Debian-version comparison
        without requiring either version to remain upstream-downloadable.

    pkg_repository_resolve_version <repository-dir> [version]
        Return the greatest currently indexed Chrome version, or validate
        that an exact requested version is present in the upstream index.
        Missing exact releases fail with an upstream-version-unavailable
        diagnostic.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate archive_regex and SHA-256 digest_type, resolve the exact
        current upstream package record, and print name, HTTPS URL, positive
        size and SHA-256 digest in the generic descriptor format.

STATUS
    Public functions return 0 on success, 1 for invalid descriptor,
    version, range or upstream evidence, and 2 for invalid invocation.

DEPENDENCIES
    http-fetch
    log
    awk
    wc

SEE ALSO
    pkg-install.lib.sh
    pkg-repository-chromium.lib.sh
    pkg-repository-artifact.lib.sh
