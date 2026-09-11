//
//  Pluralization.swift
//  CleanMyDigital
//

/// The right plural form of `singular` for `count` — "file"/"files",
/// "change"/"changes". `plural` defaults to `singular + "s"`, which covers
/// every case this app actually has; pass it explicitly for an irregular
/// plural.
///
/// Exists because completion and status messages — the most frequently
/// read text in the app — used to spell this "file(s)"/"change(s)"
/// instead, which reads as grammatically unfinished regardless of the
/// actual count.
func pluralWord(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    count == 1 ? singular : (plural ?? singular + "s")
}

/// "N word" with the right plural form — "1 file", "5 files".
func pluralized(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    "\(count) \(pluralWord(count, singular, plural: plural))"
}
