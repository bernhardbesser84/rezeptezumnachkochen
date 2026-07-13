import receive_sharing_intent

/// iPhone Teilen-Button: leitet geteilte Links direkt in die App.
class ShareViewController: RSIShareViewController {
  override func shouldAutoRedirect() -> Bool {
    return true
  }
}
