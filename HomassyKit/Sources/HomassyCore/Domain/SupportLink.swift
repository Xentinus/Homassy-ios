import Foundation

/// The only place the support URL is written down. It is our own URL, which redirects to the
/// donation platform, so the destination can change without an app update (guide §9.2).
/// D-08/D-09 (donation platform; owning homassy.com with a live /support redirect) must be
/// settled before release.
public enum SupportLink {
    public static let url = URL(string: "https://homassy.com/support")!
}
