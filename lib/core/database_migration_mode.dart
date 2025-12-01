enum DataLayout { topLevel, subcollections, dual }

// Toggle the data model used by the client during migration.
// dual: read new subcollections first and fallback to top-level for legacy, write to both.
const DataLayout kDataLayout = DataLayout.dual;
