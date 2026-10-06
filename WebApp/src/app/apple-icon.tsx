import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div style={{ width: 180, height: 180, display: "flex", alignItems: "center", justifyContent: "center", background: "#0d73d9" }}>
        <svg width="180" height="180" viewBox="0 0 64 64">
          <path d="M32 11c7 10 15 18.5 15 28a15 15 0 0 1-30 0c0-9.5 8-18 15-28z" fill="#fff" />
          <path d="M25 40.5h14M25 46h9" stroke="#0d73d9" strokeWidth="3.4" strokeLinecap="round" />
        </svg>
      </div>
    ),
    size,
  );
}
