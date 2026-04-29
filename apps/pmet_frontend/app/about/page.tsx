'use client';

import { useTranslation } from '@/lib/i18n';

export default function AboutPage() {
  const { t, locale } = useTranslation();
  const langSuffix = locale === 'zh' ? 'cn' : 'en';
  return (
    <div className="max-w-5xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">{t('about.title')}</h1>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">{t('about.what.heading')}</h2>
        <p className="text-slate-600 mb-4">{t('about.what.intro')}</p>
        <ul className="list-disc list-inside text-slate-600 space-y-2">
          <li>{t('about.what.bullet1')}</li>
          <li>{t('about.what.bullet2')}</li>
          <li>{t('about.what.bullet3')}</li>
          <li>{t('about.what.bullet4')}</li>
        </ul>
      </div>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">{t('about.modes.heading')}</h2>

        <div className="space-y-4">
          <div>
            <h3 className="font-medium text-slate-900">{t('about.modes.pre.title')}</h3>
            <p className="text-slate-600 text-sm">{t('about.modes.pre.desc')}</p>
          </div>

          <div>
            <h3 className="font-medium text-slate-900">{t('about.modes.full.title')}</h3>
            <p className="text-slate-600 text-sm">{t('about.modes.full.desc')}</p>
          </div>

          <div>
            <h3 className="font-medium text-slate-900">{t('about.modes.intervals.title')}</h3>
            <p className="text-slate-600 text-sm">{t('about.modes.intervals.desc')}</p>
          </div>

          <div className="pt-4 border-t border-slate-200">
            <h3 className="font-medium text-slate-900">{t('about.modes.elements.title')}</h3>
            <p className="text-slate-600 text-sm mb-4">{t('about.modes.elements.desc')}</p>
            <img
              src={`/figures/gff3-element-options-${langSuffix}.svg`}
              alt={t('about.modes.elements.figure_alt')}
              className="w-full rounded-lg border border-slate-200 bg-white"
            />
            <p className="mt-3 text-center text-xs text-slate-500">{t('about.modes.elements.figure_caption')}</p>
          </div>
        </div>
      </div>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">{t('about.cite.heading')}</h2>
        <p className="text-slate-600">{t('about.cite.intro')}</p>
        <blockquote className="border-l-4 border-primary-500 pl-4 mt-4 text-slate-600 italic">
          {t('about.cite.quote')}
        </blockquote>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">{t('about.resources.heading')}</h2>
        <ul className="space-y-2">
          <li>
            <a
              href="https://github.com/duocang/PMET_project"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-700 hover:underline"
            >
              {t('about.resources.github')}
            </a>
          </li>
          <li>
            <a
              href="http://pmet.online"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-700 hover:underline"
            >
              {t('about.resources.online')}
            </a>
          </li>
        </ul>
      </div>
    </div>
  );
}
