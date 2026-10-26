NAME
    pkg-repository-chromium.lib.sh - Chromium snapshot repository adapter

DESCRIPTION
    Implements the chromium repository type against the official
    chromium-browser-snapshots object service. The repository descriptor
    contains exactly:

        type = chromium
        platform = Linux_x64 | Mac | Mac_Arm | Win_x64 | Win_Arm64

    The configured platform determines the chromium snapshot object and
    its chrome-linux.zip, chrome-mac.zip or chrome-win.zip archive.
    Latest selection requests the platform's LAST_CHANGE object and
    validates the corresponding snapshot metadata. Exact version
    selection validates that snapshot object's availability.

    The object metadata supplies the exact object name, positive size
    and Base64 md5Hash. The adapter validates and converts the digest to
    hexadecimal MD5 without weakening the generic artifact-integrity
    check. The catalog range must require digest_type = md5, provide
    matching archive_regex and must not provide digest_regex.

FUNCTIONS
    pkg_repository_compare_versions <repository-dir> <left> <right>
        Print -1, 0 or 1 using numeric ordering of decimal snapshot
        positions. In this implementation both snapshots are validated
        against live metadata before comparison, including equality.
        This upstream dependency for historical comparisons remains
        pending realignment with PACKAGE-MODEL.md local ordering policy.

    pkg_repository_resolve_version <repository-dir> [version]
        Resolve and validate the current platform LAST_CHANGE snapshot,
        or validate and return an exact requested decimal snapshot
        position when its metadata is available.

    pkg_repository_resolve_artifact <repository-dir> <range-dir> <version>
        Validate the snapshot and the catalog archive/digest rules,
        then print its canonical name, HTTPS media URL, positive size
        and MD5 digest for the generic verified downloader.

STATUS
    Public functions return 0 on success, 1 for invalid repository,
    version, range or upstream evidence, and 2 for invalid invocation.

DEPENDENCIES
    json.lib.sh
    http-fetch
    awk
    wc

SEE ALSO
    pkg-install.lib.sh
    pkg-repository-chrome.lib.sh
    pkg-repository-artifact.lib.sh
