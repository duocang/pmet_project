'use client';

import { useTranslation } from '@/lib/i18n';

interface ParameterPanelProps {
  mode: 'promoters_pre' | 'promoters' | 'intervals';
  params: {
    ic_threshold: number;
    max_match: number;
    promoter_num: number;
    fimo_threshold: number;
    promoter_length?: number;
    utr5?: string;
    promoters_overlap?: string;
  };
  onChange: (params: Record<string, any>) => void;
  /** Pre-baked values shown (disabled) in promoters_pre mode. */
  fixedParams?: {
    promoter_length?: number;
    promoter_num?: number;
    max_match?: number;
    fimo_threshold?: number;
    ic_threshold?: number;
    utr5?: string;
    promoters_overlap?: string;
  };
}

const DISABLED_CLASS = 'disabled:bg-slate-100 disabled:text-slate-500 disabled:cursor-not-allowed';

export default function ParameterPanel({ mode, params, onChange, fixedParams }: ParameterPanelProps) {
  const { t } = useTranslation();
  const isPre = mode === 'promoters_pre';

  // In promoters_pre, display values come from fixedParams (baked into the
  // index); fall back to the user's params state if metadata is missing.
  const promoterLengthValue = isPre ? (fixedParams?.promoter_length ?? params.promoter_length ?? 1000) : (params.promoter_length ?? 1000);
  const promoterNumValue = isPre ? (fixedParams?.promoter_num ?? params.promoter_num) : params.promoter_num;
  const maxMatchValue = isPre ? (fixedParams?.max_match ?? params.max_match) : params.max_match;
  const fimoThresholdValue = isPre ? (fixedParams?.fimo_threshold ?? params.fimo_threshold) : params.fimo_threshold;
  const icThresholdValue = isPre ? (fixedParams?.ic_threshold ?? params.ic_threshold) : params.ic_threshold;
  const utr5Value = isPre ? (fixedParams?.utr5 ?? params.utr5 ?? 'No') : (params.utr5 ?? 'No');
  const overlapValue = isPre
    ? (fixedParams?.promoters_overlap ?? params.promoters_overlap ?? 'NoOverlap')
    : (params.promoters_overlap ?? 'NoOverlap');

  // Ensure the disabled select's current value is always a valid option,
  // even if the metadata has a non-standard number.
  const withValue = <T extends number>(opts: T[], v: T) =>
    (opts.includes(v) ? opts : [...opts, v].sort((a, b) => a - b));

  const promoterLengthOptions = isPre ? withValue([500, 1000, 1500, 2000], promoterLengthValue) : [500, 1000, 1500, 2000];
  const promoterNumOptions = isPre ? withValue([2000, 3000, 4000, 5000, 10000], promoterNumValue) : [2000, 3000, 4000, 5000, 10000];
  const maxMatchOptions = isPre ? withValue([2, 3, 4, 5, 10, 15, 20], maxMatchValue) : [2, 3, 4, 5, 10, 15, 20];
  const fimoOptions = isPre
    ? withValue([0.000001, 0.00001, 0.0001, 0.001, 0.01, 0.05], fimoThresholdValue)
    : [0.000001, 0.00001, 0.0001, 0.001, 0.01, 0.05];
  const icOptions = isPre ? withValue([2, 4, 8, 10, 16, 24, 32], icThresholdValue) : [2, 4, 8, 10, 16, 24, 32];

  const fimoLabel = (v: number) => {
    if (v >= 0.01) return String(v);
    // Render small values as 1e-N for readability.
    const exp = Math.round(Math.log10(v));
    return `1e${exp}`;
  };

  const showUtrOverlap = mode === 'promoters' || isPre;

  return (
    <div className="card">
      <h3 className="text-lg font-semibold mb-4">{t('params.heading')}</h3>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div>
          <label className="label">{t('params.promoter_length')}</label>
          <select
            className={`select-field ${DISABLED_CLASS}`}
            value={promoterLengthValue}
            onChange={(e) => onChange({ promoter_length: parseInt(e.target.value) })}
            disabled={isPre}
          >
            {promoterLengthOptions.map((n) => (
              <option key={n} value={n}>{n} bp</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">{t('params.max_match')}</label>
          <select
            className={`select-field ${DISABLED_CLASS}`}
            value={maxMatchValue}
            onChange={(e) => onChange({ max_match: parseInt(e.target.value) })}
            disabled={isPre}
          >
            {maxMatchOptions.map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">{t('params.promoter_num')}</label>
          <select
            className={`select-field ${DISABLED_CLASS}`}
            value={promoterNumValue}
            onChange={(e) => onChange({ promoter_num: parseInt(e.target.value) })}
            disabled={isPre}
          >
            {promoterNumOptions.map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">{t('params.fimo_threshold')}</label>
          <select
            className={`select-field ${DISABLED_CLASS}`}
            value={fimoThresholdValue}
            onChange={(e) => onChange({ fimo_threshold: parseFloat(e.target.value) })}
            disabled={isPre}
          >
            {fimoOptions.map((v) => (
              <option key={v} value={v}>{fimoLabel(v)}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="label">{t('params.ic_threshold')}</label>
          <select
            className={`select-field ${DISABLED_CLASS}`}
            value={icThresholdValue}
            onChange={(e) => onChange({ ic_threshold: parseInt(e.target.value) })}
            disabled={isPre}
          >
            {icOptions.map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>

        {showUtrOverlap && (
          <>
            <div>
              <label className="label">{t('params.utr5')}</label>
              <select
                className={`select-field ${DISABLED_CLASS}`}
                value={utr5Value}
                onChange={(e) => onChange({ utr5: e.target.value })}
                disabled={isPre}
              >
                <option value="Yes">{t('params.utr5.yes')}</option>
                <option value="No">{t('params.utr5.no')}</option>
              </select>
            </div>

            <div>
              <label className="label">{t('params.overlap')}</label>
              <select
                className={`select-field ${DISABLED_CLASS}`}
                value={overlapValue}
                onChange={(e) => onChange({ promoters_overlap: e.target.value })}
                disabled={isPre}
              >
                <option value="NoOverlap">{t('params.overlap.no')}</option>
                <option value="AllowOverlap">{t('params.overlap.allow')}</option>
              </select>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
