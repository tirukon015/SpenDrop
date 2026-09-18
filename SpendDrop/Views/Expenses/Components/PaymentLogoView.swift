import SwiftUI

/// Renders either a custom provider logo (TNG, Maybank, CIMB, RHB, Apple Pay) or the fallback SF Symbol
public struct ProviderLogoView: View {
    public let source: PaymentSource
    public var size: CGFloat
    public var cornerRadius: CGFloat?

    public init(source: PaymentSource, size: CGFloat = 20, cornerRadius: CGFloat? = nil) {
        self.source = source
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if let assetName = source.logoAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? (size * 0.22), style: .continuous))
        } else {
            Image(systemName: source.icon)
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(source.brandColor)
                .frame(width: size, height: size)
        }
    }
}

/// Renders payment badge with logo(s) and label (handles Apple Pay + underlying bank combination)
public struct PaymentMethodBadgeView: View {
    public let paymentSource: PaymentSource
    public let underlyingBank: PaymentSource?
    public var iconSize: CGFloat
    public var showText: Bool
    public var font: Font

    public init(
        paymentSource: PaymentSource,
        underlyingBank: PaymentSource? = nil,
        iconSize: CGFloat = 14,
        showText: Bool = true,
        font: Font = .caption2
    ) {
        self.paymentSource = paymentSource
        self.underlyingBank = underlyingBank
        self.iconSize = iconSize
        self.showText = showText
        self.font = font
    }

    public var displayText: String {
        if paymentSource == .applePay, let bank = underlyingBank, bank != .unknown {
            return "Apple Pay • \(bank.shortName)"
        }
        return paymentSource.shortName
    }

    public var body: some View {
        HStack(spacing: 4) {
            ProviderLogoView(source: paymentSource, size: iconSize)

            if paymentSource == .applePay, let bank = underlyingBank, bank != .unknown {
                ProviderLogoView(source: bank, size: iconSize)
            }

            if showText {
                Text(displayText)
                    .font(font)
                    .fontWeight(.medium)
            }
        }
    }
}
