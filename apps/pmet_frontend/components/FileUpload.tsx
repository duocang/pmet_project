'use client';

import { useCallback, useState } from 'react';
import { useDropzone, type FileError, type FileRejection } from 'react-dropzone';
import toast from 'react-hot-toast';
import { useTranslation } from '@/lib/i18n';

interface FileUploadProps {
  label: string;
  accept?: string;
  onUpload: (file: File) => Promise<void>;
  currentFile?: string;
  helpText?: string;
  required?: boolean;
  /** Optional URL to a demo file. If set, a small "Use example" link appears. */
  demoUrl?: string;
  /** Filename to give the fetched demo file. */
  demoFilename?: string;
}

export default function FileUpload({
  label,
  accept,
  onUpload,
  currentFile,
  helpText,
  required = false,
  demoUrl,
  demoFilename,
}: FileUploadProps) {
  const { t } = useTranslation();
  const [loadingDemo, setLoadingDemo] = useState(false);
  const acceptedExtensions = accept
    ? accept
        .split(',')
        .map((ext) => ext.trim().toLowerCase())
        .filter(Boolean)
    : [];

  const onDrop = useCallback(
    async (acceptedFiles: File[]) => {
      if (acceptedFiles.length === 0) return;

      const file = acceptedFiles[0];
      try {
        await onUpload(file);
        toast.success(`${file.name} — ${t('fileupload.toast.uploaded')}`);
      } catch (error) {
        toast.error(`${t('fileupload.toast.failed')}: ${file.name}`);
        console.error(error);
      }
    },
    [onUpload, t]
  );

  const validateFileType = useCallback(
    (file: File): FileError | null => {
      if (acceptedExtensions.length === 0) {
        return null;
      }

      const fileName = file.name.toLowerCase();
      const isAccepted = acceptedExtensions.some((ext) => fileName.endsWith(ext));
      if (isAccepted) {
        return null;
      }

      return {
        code: 'file-invalid-type',
        message: `File type must be ${acceptedExtensions.join(', ')}`,
      };
    },
    [acceptedExtensions]
  );

  const onDropRejected = useCallback(
    (fileRejections: FileRejection[]) => {
      const firstError = fileRejections[0]?.errors[0];
      toast.error(firstError?.message || t('fileupload.toast.unsupported'));
    },
    [t]
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    onDropRejected,
    multiple: false,
    validator: acceptedExtensions.length > 0 ? validateFileType : undefined,
  });

  const useExample = useCallback(async () => {
    if (!demoUrl) return;
    setLoadingDemo(true);
    try {
      const res = await fetch(demoUrl);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const blob = await res.blob();
      const filename = demoFilename || demoUrl.split('/').pop() || 'example';
      const file = new File([blob], filename, { type: blob.type || 'application/octet-stream' });
      await onUpload(file);
      toast.success(`${t('fileupload.toast.example_loaded')} ${filename}`);
    } catch (e) {
      toast.error(t('fileupload.toast.example_failed'));
      console.error(e);
    } finally {
      setLoadingDemo(false);
    }
  }, [demoUrl, demoFilename, onUpload, t]);

  return (
    <div className="mb-4">
      <div className="flex items-center justify-between mb-1">
        <label className="label mb-0">
          {label}
          {required && <span className="text-red-500 ml-1">*</span>}
        </label>
        {demoUrl && (
          <button
            type="button"
            onClick={useExample}
            disabled={loadingDemo}
            className="text-xs font-medium text-primary-700 hover:text-primary-800 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center gap-1"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="13 2 13 9 20 9" />
              <path d="M20 9v11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h7" />
            </svg>
            {loadingDemo ? t('fileupload.loading') : t('fileupload.use_example')}
          </button>
        )}
      </div>
      <div
        {...getRootProps()}
        className={`file-upload ${isDragActive ? 'border-primary-500 bg-primary-50' : ''}`}
      >
        <input {...getInputProps({ accept })} />
        {currentFile ? (
          <div className="text-green-600 font-medium">
            <svg className="inline w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
            {currentFile}
          </div>
        ) : isDragActive ? (
          <p className="text-primary-600">{t('fileupload.drop_active')}</p>
        ) : (
          <p className="text-slate-500">{t('fileupload.drop_idle')}</p>
        )}
      </div>
      {helpText && (
        <p className="mt-1 text-sm text-slate-500">{helpText}</p>
      )}
    </div>
  );
}
