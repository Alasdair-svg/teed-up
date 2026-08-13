import receive_sharing_intent

/// Share Extension entry point (spec A6).
///
/// Inherits all image/text hand-off behaviour from `RSIShareViewController`
/// (provided by the `receive_sharing_intent` plugin) — it copies the shared
/// image into the app group container and redirects straight into
/// "All Teed Up" (no extra compose UI), landing on the scan review screen.
class ShareViewController: RSIShareViewController {
}
