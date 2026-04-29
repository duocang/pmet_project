'use client';

import { useEffect, useState } from 'react';

interface ZoomableImageProps {
  src: string;
  alt: string;
  className?: string;
}

export default function ZoomableImage({ src, alt, className }: ZoomableImageProps) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [open]);

  return (
    <>
      <img
        src={src}
        alt={alt}
        className={`${className ?? ''} cursor-zoom-in transition-opacity hover:opacity-90`}
        onClick={() => setOpen(true)}
      />
      {open && (
        <div
          onClick={() => setOpen(false)}
          className="zoom-overlay fixed inset-0 z-[60] flex items-center justify-center bg-black/80 p-6 cursor-zoom-out backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-label={alt}
        >
          <img
            src={src}
            alt={alt}
            className="zoom-content max-h-full max-w-full object-contain rounded shadow-2xl"
          />
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); setOpen(false); }}
            className="absolute top-4 right-4 rounded-full bg-white/10 px-3 py-1 text-2xl leading-none text-white hover:bg-white/20"
            aria-label="Close"
          >
            ×
          </button>
        </div>
      )}
    </>
  );
}
