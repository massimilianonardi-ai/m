NAME
    json.lib.sh - selected JSON object and array field extraction

DESCRIPTION
    Shell functions for parsing trusted JSON on standard input and extracting
    requested fields for the m package repository adapters. No Node.js runtime
    is required.

FUNCTIONS
    json_object_fields <field>...
        Extract the selected fields from a JSON object read from standard input.

    json_array_object_fields <field>...
        Extract the selected fields from each object in a JSON array.

    json_object_array_object_fields <array-field> <field>...
        Extract the selected fields from objects in the named array property
        of a JSON object.

    json_object_read <field> <variable> [<field> <variable>...]
        Read selected JSON object fields from standard input into the named
        current-shell variables. Argument pairs map JSON field names to
        receiving shell variable names.

    Field and variable identifiers must be valid shell-style identifiers.
    Extraction functions emit a tab-separated field record stream; see their
    callers for the required record shape. Invalid arguments return nonzero;
    malformed or unsupported JSON also fails rather than silently succeeding.

DEPENDENCIES
    POSIX sh and awk.

SEE ALSO
    pkg-repository-github.lib.sh
