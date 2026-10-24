NAME
    pkg-install.lib.sh - orchestrate recursive package installation

DESCRIPTION
    pkg-install.lib.sh implements the public pkg install command. It validates the
    complete original request list before catalog initialization, dependency
    planning or package installation. Only after every request is syntactically
    valid does it initialize one installation catalog snapshot and call pkg depend
    with the untouched original request list.

    Dependency concrete identities returned by pkg depend are prepended to the
    original request list. The dependency entries are already concrete; original
    roots deliberately retain their requested form and are resolved by
    pkg_install_one against the same installation catalog snapshot when their turn
    in the install sequence is reached. This preserves one dependency-planning
    authority while still installing dependencies before requested roots.

    pkg install owns request installation, not dependency discovery. Each package
    selected for installation is resolved to its package range, its artifact is
    downloaded and extracted, provider conformance is validated, and the package
    is integrated. An already installed concrete dependency is reused directly
    without redundant catalog resolution.

FUNCTIONS
    pkg_install <package-spec>...
        Validate every original package specification first. If any request is
        syntactically invalid, fail before dependency planning and install nothing.
        Otherwise initialize the catalog snapshot, invoke pkg depend exactly once
        with the untouched original requests, prepend the returned dependency
        concretes to those original requests, and install the resulting sequence.

        A dependency-planning failure after valid request syntax is an execution
        failure, not an invalid-arguments condition. Diagnostics emitted by
        pkg depend remain visible before the top-level pkg-install
        dependency-unresolvable failure.

    pkg_install_one <package-spec>
        Resolve one package specification against the current installation catalog
        snapshot and install its concrete identity unless that concrete is already
        installed.

DEPENDENCIES
    pkg-common.lib.sh
    pkg-catalog.lib.sh
    pkg-depend.lib.sh
    pkg-download.lib.sh
    pkg-extract.lib.sh
    pkg-integration.lib.sh

SEE ALSO
    pkg
    pkg-depend.lib.sh
    pkg-catalog.lib.sh
