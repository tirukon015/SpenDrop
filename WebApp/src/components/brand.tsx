/** The SpenDrop mark: a drop with a receipt line, in the SpenDrop blue. Pure SVG, scales anywhere. */
export function BrandMark({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden className={className}>
      <rect width="64" height="64" rx="15" fill="#0d73d9" />
      <path d="M32 11c7 10 15 18.5 15 28a15 15 0 0 1-30 0c0-9.5 8-18 15-28z" fill="#fff" />
      <path d="M25 40.5h14M25 46h9" stroke="#0d73d9" strokeWidth="3.4" strokeLinecap="round" />
    </svg>
  );
}
