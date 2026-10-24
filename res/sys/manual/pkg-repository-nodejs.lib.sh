NAME
    pkg-repository-nodejs.lib.sh - Node.js distribution repository adapter

DESCRIPTION
    Implements release discovery, local version ordering, exact release
    validation and artifact resolution using the official nodejs.org
    distribution service.

    Repository metadata contains:
        type = nodejs
        major = <positive decimal major version>

    and requires typed download/ and metadata/ descriptors handled by
    pkg-repository-artifact.lib.sh.

    Release discovery uses https://nodejs.org/dist/index.json and selects only
    v<major>.<minor>.<patch> releases matching the configured major line.
    Artifact URL construction and checksum extraction remain delegated to the
    existing catalog descriptors. Current Node.js Linux streams use nodejs.org
    template downloads and SHA-256 checksum manifests.

    Version comparison is local and does not depend on historical upstream
    artifact availability.

    Failed upstream transfers emit contextual internal diagnostics identifying
    the adapter operation and requested URL. These diagnostics do not change the
    public adapter function signatures or status classes.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print releases from the configured major line reported by the official
        Node.js distribution index.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 using component-wise numeric ordering without an
        upstream request.

    pkg_repository_resolve_version <repository-dir> [version]
        Resolve the numerically greatest current release in the configured
        major line, or validate and print an exact requested release.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate the release, resolve the catalog-defined artifact URL, enforce
        archive_regex, and obtain positive size plus digest through the
        configured typed metadata handler.

STATUS
    Public functions return 0 on success, 1 when repository, range or upstream
    data does not satisfy the adapter contract, and 2 for invalid invocation.

DEPENDENCIES
    json.lib.sh
    pkg-repository-artifact.lib.sh
    http-fetch

SEE ALSO
    pkg-repository-artifact.lib.sh
    pkg-install.lib.sh
