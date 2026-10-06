"use client";

// In-browser OCR with tesseract.js (free, open source, runs locally — the image never leaves the device).
// Loaded only when the user scans a receipt, so it adds nothing to normal page loads.
import type { OcrLine } from "./parse";

/** Resize + re-encode a photo/screenshot so receipts stay small but readable (≤1600 px, WebP). */
export async function compressImage(file: Blob, maxSide = 1600, quality = 0.82): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/webp", quality));
  if (blob && blob.type === "image/webp") return blob;
  return (await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", quality))) ?? file;
}

export async function recognizeText(image: Blob, onProgress?: (fraction: number) => void): Promise<OcrLine[]> {
  const { createWorker } = await import("tesseract.js");
  const worker = await createWorker("eng", 1, {
    logger: (m: { status: string; progress: number }) => {
      if (m.status === "recognizing text") onProgress?.(m.progress);
    },
  });
  try {
    const { data } = await worker.recognize(image, {}, { blocks: true });
    const lines: OcrLine[] = [];
    for (const block of data.blocks ?? []) for (const para of block.paragraphs) for (const line of para.lines) {
      lines.push({ text: line.text.trim(), confidence: (line.confidence ?? 0) / 100 });
    }
    if (lines.length === 0 && data.text) return data.text.split("\n").map((text) => ({ text, confidence: (data.confidence ?? 0) / 100 }));
    return lines.filter((l) => l.text);
  } finally {
    await worker.terminate();
  }
}
