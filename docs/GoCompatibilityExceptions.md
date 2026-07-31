# Go Compatibility Exceptions

The production Go Miranda interpreter has no approved compatibility exceptions.

An exception may be added only when exact Zig-reference behavior is unsuitable
for the supported macOS ARM64 product and the change has been explicitly
approved. Each exception must contain:

- a stable identifier and owner;
- the affected command, language feature, or platform behavior;
- the Zig-reference behavior and the proposed Go behavior;
- user impact and rationale;
- a focused test proving the intentional difference;
- an approval record;
- an expiry condition or a decision that the difference is permanent.

Expected-output files must not be changed to hide an unapproved difference.
Temporary implementation gaps, test flakes, timeouts, and performance problems
are not compatibility exceptions.
