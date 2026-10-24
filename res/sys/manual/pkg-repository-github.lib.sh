NAME
    pkg-repository-github.lib.sh - GitHub Releases package repository adapter

DESCRIPTION
    Implements package version discovery, ordering, exact release validation and
    artifact resolution for repositories whose release authority is GitHub
    Releases.

    Repository metadata contains:

        type = github
        owner
        repository

    An optional repository/versions file contains known stable release tags,
    one per line, in ascending GitHub chronology. Both-indexed historical
    comparisons and exact indexed-version resolution avoid discovery HTTP.
    Unknown tags still use live lookup. Malformed indices fail closed.

    and may additionally contain the optional typed artifact override
    subdirectories:

        download/
        metadata/

    Without overrides, artifact name, download URL, byte size and optional
    SHA-256 digest are resolved from exactly one matching uploaded GitHub release
    asset, preserving the complete default behavior of the github repository
    type.

    With an artifact override, GitHub remains the release authority: the exact
    requested non-draft, non-prerelease release is still validated through the
    GitHub Releases API. Only the responsibility represented by the present
    override is delegated to pkg-repository-artifact.lib.sh. A non-overridden
    artifact responsibility continues to use the GitHub release asset.

    Stable releases are ordered by their GitHub created_at and published_at
    timestamps rather than by interpreting tag text as semantic or numeric
    versions.

    Failed upstream transfers emit contextual internal diagnostics identifying
    the adapter operation and requested URL. These diagnostics do not change the
    public adapter function signatures or status classes.

FUNCTIONS
    pkg_repository_list_versions <repository-dir>
        Print available non-draft, non-prerelease GitHub release tags in
        ascending GitHub release chronology.

    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 according to GitHub release chronology. Equality is
        resolved locally; indexed historical comparisons also avoid HTTP.

    pkg_repository_resolve_version <repository-dir> [version]
        Validate and print an exact stable GitHub release tag, or resolve and
        print the GitHub latest stable release when version is omitted.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Print the canonical package artifact descriptor. The range archive_regex
        must match the resolved artifact name. Without metadata override,
        digest_type is optional and, when present, must be sha256 as supplied by
        the GitHub asset. With metadata override, digest requirements are owned
        by the selected typed metadata handler while the canonical descriptor
        format remains unchanged.

STATUS
    Public functions return 0 on success, 1 when repository/upstream/range data
    does not satisfy the adapter contract, and 2 for invalid function invocation.

DEPENDENCIES
    json.lib.sh
    pkg-repository-artifact.lib.sh
    http-fetch

SEE ALSO
    pkg-repository-artifact.lib.sh
    pkg-install.lib.sh
