import { ImageResponse } from "next/og";

// PNG app icons for the manifest / home screen, generated from the SpenDrop mark (no binary files in git).
export async function GET(_request: Request, { params }: { params: Promise<{ size: string }> }) {
  const { size: raw } = await params;
  const maskable = raw === "maskable";
  const size = maskable ? 512 : raw === "192" ? 192 : raw === "180" ? 180 : 512;
  const pad = maskable ? size * 0.12 : 0;
  const inner = size - pad * 2;
  return new ImageResponse(
    (
      <div style={{ width: size, height: size, display: "flex", alignItems: "center", justifyContent: "center", background: "#0d73d9" }}>
        <svg width={inner} height={inner} viewBox="0 0 64 64">
          <rect width="64" height="64" rx={maskable ? 0 : 15} fill="#0d73d9" />
          <path d="M32 11c7 10 15 18.5 15 28a15 15 0 0 1-30 0c0-9.5 8-18 15-28z" fill="#fff" />
          <path d="M25 40.5h14M25 46h9" stroke="#0d73d9" strokeWidth="3.4" strokeLinecap="round" />
        </svg>
      </div>
    ),
    { width: size, height: size },
  );
}
