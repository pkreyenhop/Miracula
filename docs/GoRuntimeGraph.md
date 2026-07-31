# Go Runtime Graph Ownership

Miranda graph cells live in an interpreter-owned `graphstore.Heap`. Go owns the
backing slices, while the heap retains a logical mark-and-sweep collector for
Miranda's bounded-heap behavior, deterministic reclamation tests, and graph
checkpoint semantics.

The collector never scans the native Go stack. A graph value that must survive
an allocation is reachable from one of:

- a cell already reachable from a registered root;
- a value registered with `Heap.Roots.Root` or `RootSlice`;
- the head or tail arguments of the allocation currently in progress.

Root guards are lexical and close in LIFO order. Interpreter reset is illegal
while guards remain active. `SetForceCollect(true)` collects before every
allocation and is the test mode that detects missing roots. Collection and
graph traversal are iterative so deep lazy graphs do not consume the Go call
stack.

Heap checkpoints copy cell, liveness, and free-list state. Resource checkpoints
are separate: restoring one closes resources created after it. Resource IDs
increase monotonically for the lifetime of a table and are not reused by reset.
Reset closes every open interpreter-owned resource.

This package is not internally synchronized. One interpreter owns one heap and
uses it from one evaluation goroutine. Separate interpreters and heaps may run
concurrently. Cancellation is communicated through interpreter state rather
than concurrent graph mutation.
