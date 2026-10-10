/// Returns whether the project grid can be laid out safely.
///
/// Sliver grid delegates assert that their cross-axis extent is positive. Home
/// can briefly receive a zero or unbounded width while a compact surface is
/// attaching or changing tabs, so callers must render a placeholder instead
/// of constructing a grid for those constraints.
bool hasUsableProjectGridWidth(double width) => width.isFinite && width > 0.0;
