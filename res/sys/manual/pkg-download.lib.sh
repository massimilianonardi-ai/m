NAME
    pkg-download.lib.sh - validate and download resolved package artifacts

DESCRIPTION
    Implements the generic package artifact download boundary.

    pkg_download reads one artifact descriptor from standard input. A descriptor
    contains exactly one artifact name, one positive expected size, zero or one
    digest, and one or more ordered URL candidates for the same artifact.

    URL candidates are attempted in descriptor order. A candidate is accepted
    only after its transferred file matches the expected size and, when present,
    the expected digest. Failed or invalid candidate output is removed before the
    next candidate is attempted. If no candidate validates, the operation fails.

    Repository-specific mirror construction belongs to repository adapters; this
    library does not contain provider-specific mirror policy.

FUNCTIONS
    pkg_download <staging-dir>
        Read the resolved artifact descriptor from standard input, download and
        validate the artifact into <staging-dir>, then print the absolute artifact
        pathname followed by newline.

        Accepted descriptor fields are:

            name=<basename>
            url=<http-or-https-url>
            url=<additional-candidate-url>   (optional/repeatable)
            size=<positive-decimal-bytes>
            digest=md5:<hex>                 (optional)
            digest=sha256:<hex>              (optional)
            digest=sha512:<hex>              (optional)

        name, size and digest (when supplied) are single-valued. At least one url
        is required. Every url candidate must represent the same artifact identity.

        Returns 0 only when one candidate transfers and satisfies all configured
        verification. Returns 1 for descriptor, transfer or verification failure,
        and 2 for invalid function invocation.

DEPENDENCIES
    http-fetch
    digest

SEE ALSO
    pkg-install.lib.sh
    pkg-repository-geoserver.lib.sh
