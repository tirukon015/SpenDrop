import Image from "next/image";

/** The SpenDrop app icon (same artwork as the iOS app icon), with iOS-style rounded corners. */
export function BrandMark({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <Image
      src="/icons/logo-256.png"
      alt=""
      aria-hidden
      width={size}
      height={size}
      priority
      className={className}
      style={{ borderRadius: size * 0.2237, width: size, height: size }}
    />
  );
}
