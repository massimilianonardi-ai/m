NAME
    pkg-repository-artifact.lib.sh - typed package artifact handlers

DESCRIPTION
    Provides reusable trusted handlers for package artifact-resolution
    responsibilities. Repository type adapters remain complete implementations;
    optional catalog overrides replace only the responsibility represented by
    their typed subdescriptor.

    Download descriptors currently support:

        type = template-url
        name-template
        url-template

    name-template accepts {version}. url-template accepts {version} and {name}.
    Unknown placeholders are invalid.

    Metadata descriptors currently support:

        checksum-sidecar
        checksum-manifest
        sourceforge-rss

    checksum-sidecar requires url-template plus record-format = digest-name or
    digest-only. digest-name accepts exactly one checksum record containing the
    digest and the resolved artifact name; digest-only accepts exactly one record
    containing only the digest. checksum-manifest requires url-template. These
    handlers resolve size from the HTTPS
    artifact URL and validate exactly one checksum record for the resolved name.

    sourceforge-rss requires project and path-template. path-template accepts
    {version}; the RSS entry matching the exact download URL supplies authoritative
    positive byte size and digest.

    The digest algorithm is always supplied separately by the caller from the
    package range digest_type contract. A metadata handler never redefines it.

FUNCTIONS
    pkg_repository_artifact_overrides_validate <repository-dir>
        Validate any present download/ and metadata/ typed subdescriptors.

    pkg_repository_artifact_download_resolve <download-dir> <version>
        Resolve a typed download descriptor and print one tab-separated artifact
        name and HTTPS URL.

    pkg_repository_artifact_download_template_url <name-template> <url-template> <version>
        Resolve the template-url mechanism directly and print one tab-separated
        artifact name and HTTPS URL. This public mechanism entrypoint lets a
        complete repository type reuse the trusted template implementation without
        requiring a catalog override.

    pkg_repository_artifact_metadata_resolve <metadata-dir> <digest-type> <version> <name> <download-url>
        Resolve a typed metadata descriptor and print one tab-separated positive
        byte size and <algorithm>:<hex> digest.

    pkg_repository_artifact_metadata_checksum_sidecar <metadata-url> <record-format> <digest-type> <name> <download-url>
        Resolve the checksum-sidecar mechanism directly. record-format is
        digest-name or digest-only. This public mechanism entrypoint lets a
        complete repository type reuse the trusted sidecar implementation without
        requiring a catalog override.

    pkg_repository_artifact_metadata_sourceforge_rss <project> <path-template> <digest-type> <version> <name> <download-url>
        Resolve the SourceForge RSS metadata mechanism directly. This public
        mechanism entrypoint lets a complete custom repository type reuse the same
        trusted implementation without requiring a catalog override.

STATUS
    Public functions return 0 on success, 1 when descriptor/upstream data violates
    the handler contract, and 2 for invalid invocation.

DEPENDENCIES
    http-fetch
    awk
    tr
    wc

SEE ALSO
    pkg-repository-github.lib.sh
    pkg-repository-geoserver.lib.sh
    pkg-install.lib.sh
