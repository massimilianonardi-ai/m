# m

This repository contains the technical `m` foundation: the POSIX-shell
bootstrap, `pkg`, essential commands and library facilities, technical
localization and manuals, managed public TLS-CA trust, and local services.

The implementation files in this checkout were imported unchanged from
`massimilianonardi-ai/rumiai-os` revision
`673df1a2d5476ad57d54c7bc7e1fc2deeaf16195`; package-only manuals
missing from that source have been added here.

`mk` and Node.js are **not** bootstrap prerequisites. The package catalog
is kept in the separate `pkg-catalog` repository and is consulted by package
operations rather than by the `m` bootstrap.

## First-use commands

From the root of this checkout:

```sh
./m osarch update
./m osarch show
./m manual --no-pager pkg
./m lang-set
./m pkg versions nodejs
```

The last command lists installed versions and can return nonzero when none
are installed. `./m pkg install <package>` reads the selected catalog and
requires appropriate host networking, tools and authorization.

The source checkout preserves the existing `m` state and platform-selection
contract. `osarch update` materializes the platform-specific technical paths
for the current host. There is no implicit platform mutation in bootstrap.

The currently included repository adapters support GitHub, Node.js and their
shared artifact functionality. Other upstream adapter types from
`rumiai-os` are not yet included, so packages requiring them are not
installable through this restricted repository revision.

Operational manuals are under `res/sys/manual`. Current development
contracts and ongoing source-composition work live in `rumiai-dev`.

This is a technical foundation checkout, not a complete `rumiai-os` product
distribution. The first-stage extraction does not migrate host installations.
