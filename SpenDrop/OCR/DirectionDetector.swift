import Foundation

/// Suggests whether a screenshot is money coming IN, an own-account top-up/transfer, or a refund —
/// only from clear wording. Anything unclear returns no suggestion and stays a normal expense for review.
/// It never decides on its own; the user confirms on the review screen.
public enum DirectionDetector {
