'use client';

import Link from 'next/link';

function DatabaseIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <ellipse cx="12" cy="5" rx="7" ry="3" />
      <path d="M5 5v6c0 1.7 3.1 3 7 3s7-1.3 7-3V5" />
      <path d="M5 11v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6" />
    </svg>
  );
}

function GenomeIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M7 3c6 2 10 6 10 18" />
      <path d="M17 3C11 5 7 9 7 21" />
      <path d="M8.5 6.5h7" />
      <path d="M7.5 10.5h9" />
      <path d="M7.5 14.5h9" />
      <path d="M8.5 18.5h7" />
    </svg>
  );
}

function IntervalIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 7h16" />
      <path d="M4 17h16" />
      <path d="M7 7v10" />
      <path d="M17 7v10" />
      <path d="M10 12h4" />
    </svg>
  );
}

function ChartIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 19V5" />
      <path d="M4 19h16" />
      <rect x="7" y="10" width="3" height="6" rx="1" />
      <rect x="12" y="7" width="3" height="9" rx="1" />
      <rect x="17" y="12" width="3" height="4" rx="1" />
    </svg>
  );
}

const modes = [
  {
    title: 'Pre-computed Promoters',
    desc: 'Use indexed motif databases for plant species. Fastest path when a gene list is your main input.',
    href: '/submit?mode=promoters_pre',
    icon: <DatabaseIcon />,
    action: 'Start Analysis',
  },
  {
    title: 'Full Promoters',
    desc: 'Upload genome, annotation, motif database, and gene list for a fully custom promoter run.',
    href: '/submit?mode=promoters',
    icon: <GenomeIcon />,
    action: 'Build Custom Run',
  },
  {
    title: 'Intervals',
    desc: 'Analyze ChIP-seq peaks, ATAC regions, or other genomic intervals against a motif database.',
    href: '/submit?mode=intervals',
    icon: <IntervalIcon />,
    action: 'Analyze Intervals',
  },
  {
    title: 'Visualize Results',
    desc: 'Open existing PMET output files as interactive heatmaps, histograms, and searchable tables.',
    href: '/visualize',
    icon: <ChartIcon />,
    action: 'Upload Results',
  },
];

const steps = [
  { n: '01', title: 'Upload Data', desc: 'Provide the gene list and any required reference files.' },
  { n: '02', title: 'Tune Parameters', desc: 'Set motif-hit depth, FIMO threshold, promoter length, and pairing options.' },
  { n: '03', title: 'Run Worker', desc: 'The job is queued and executed asynchronously on the backend worker.' },
  { n: '04', title: 'Review Results', desc: 'Download the result archive or explore significant motif pairs visually.' },
];

export default function HomePage() {
  return (
    <div className="space-y-16 pb-14">
      <section className="hero-stage">
        <div className="hero-content">
          <p className="mb-4 text-xs font-bold uppercase tracking-[0.22em] text-teal-100">
            Cooperative motif enrichment
          </p>
          <h1 className="text-5xl font-bold leading-tight text-white md:text-6xl">
            PMET
          </h1>
          <p className="mt-4 max-w-2xl text-lg leading-8 text-teal-50 md:text-xl">
            Promoter Motif Enrichment Tool identifies cooperative transcription factor activity across homotypic and heterotypic motif combinations.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link href="/submit?mode=promoters_pre" className="btn-primary w-48">
              Start Analysis
            </Link>
            <Link href="/visualize" className="btn-secondary w-48">
              Visualize Results
            </Link>
          </div>
          <div className="mt-8 flex flex-wrap gap-3">
            <div className="w-40 rounded-lg border border-white/15 bg-white/10 px-5 py-3 text-white backdrop-blur">
              <div className="text-2xl font-bold leading-none">21</div>
              <div className="mt-1.5 text-xs text-teal-50">plant species</div>
            </div>
            <div className="w-40 rounded-lg border border-white/15 bg-white/10 px-5 py-3 text-white backdrop-blur">
              <div className="text-2xl font-bold leading-none">6</div>
              <div className="mt-1.5 text-xs text-teal-50">motif databases</div>
            </div>
          </div>
        </div>
      </section>

      <section id="modes" className="scroll-mt-24">
        <div className="mb-8 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <p className="eyebrow mb-2">Analysis entry points</p>
            <h2 className="section-heading">Choose the run that matches your inputs</h2>
          </div>
          <p className="max-w-2xl text-slate-600">
            PMET keeps fast pre-indexed workflows and fully custom uploads in the same interface, so users can move from screening to bespoke analysis without changing tools.
          </p>
        </div>

        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-4">
          {modes.map((mode) => (
            <div key={mode.title} className="mode-card group">
              <div className="mode-icon">{mode.icon}</div>
              <h3 className="text-lg font-semibold text-slate-950">{mode.title}</h3>
              <p className="mt-3 flex-1 text-sm leading-6 text-slate-600">{mode.desc}</p>
              <Link href={mode.href} className="btn-primary mt-6 w-full">
                {mode.action}
              </Link>
            </div>
          ))}
        </div>
      </section>

      <section id="how-it-works" className="scroll-mt-24">
        <div className="card">
          <div className="mb-8 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
            <div>
              <p className="eyebrow mb-2">Job lifecycle</p>
              <h2 className="section-heading">From files to ranked motif pairs</h2>
            </div>
            <Link href="/tasks" className="font-semibold text-primary-700 hover:text-primary-900">
              View My Tasks &rarr;
            </Link>
          </div>

          <div className="grid gap-4 md:grid-cols-4">
            {steps.map((step) => (
              <div key={step.n} className="rounded-lg border border-slate-200 bg-slate-50/80 p-4">
                <div className="mb-4 inline-flex rounded-md bg-white px-2.5 py-1 text-xs font-bold text-primary-700 shadow-sm">
                  {step.n}
                </div>
                <h3 className="font-semibold text-slate-950">{step.title}</h3>
                <p className="mt-2 text-sm leading-6 text-slate-600">{step.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="learn-more" className="scroll-mt-24">
        <div className="mb-8">
          <p className="eyebrow mb-2">Method context</p>
          <h2 className="section-heading">Understand what PMET is measuring</h2>
        </div>

        <div className="space-y-4">
          <details className="card group" open>
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-semibold text-slate-950">
              <span>What is PMET?</span>
              <span className="text-slate-400 transition-transform group-open:rotate-180">▾</span>
            </summary>
            <div className="mt-6 grid gap-4 md:grid-cols-2">
              <div className="rounded-lg border border-slate-200 bg-slate-50/80 p-4">
                <h4 className="font-semibold text-slate-950">Cooperative TF Detection</h4>
                <p className="mt-2 text-sm leading-6 text-slate-600">
                  Scores motif combinations within transcriptional regulatory modules, revealing TF cooperation that single-motif tests can miss.
                </p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50/80 p-4">
                <h4 className="font-semibold text-slate-950">Homotypic + Heterotypic</h4>
                <p className="mt-2 text-sm leading-6 text-slate-600">
                  Handles same-motif repeats and different-motif pairs together, avoiding a narrow one-at-a-time interpretation.
                </p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50/80 p-4">
                <h4 className="font-semibold text-slate-950">Parallel Engine</h4>
                <p className="mt-2 text-sm leading-6 text-slate-600">
                  Uses a pairing engine and fused FIMO-integrated indexing flow to scale across genome-sized motif scans.
                </p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50/80 p-4">
                <h4 className="font-semibold text-slate-950">Pre-indexed References</h4>
                <p className="mt-2 text-sm leading-6 text-slate-600">
                  Pre-computed indices for common plant references — run an analysis in <strong>minutes</strong> without uploading a genome.
                </p>
              </div>
            </div>
          </details>

          <details className="card group">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-semibold text-slate-950">
              <span>PMET Workflow</span>
              <span className="text-slate-400 transition-transform group-open:rotate-180">▾</span>
            </summary>
            <div className="mt-6">
              <img
                src="/figures/workflow_overview.png"
                alt="PMET workflow with interval option"
                className="w-full rounded-lg border border-slate-200 bg-white"
              />
              <p className="mt-4 text-center text-sm text-slate-500">
                Inputs feed into motif scanning and the PMET pairing engine, producing ranked motif-pair enrichments.
              </p>
            </div>
          </details>

          <details className="card group">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-semibold text-slate-950">
              <span>Motif Combinations</span>
              <span className="text-slate-400 transition-transform group-open:rotate-180">▾</span>
            </summary>
            <div className="mt-6 grid gap-6 md:grid-cols-2">
              <div>
                <h4 className="mb-3 text-center font-semibold text-slate-950">Homotypic</h4>
                <img
                  src="/figures/pmet_homotypic.png"
                  alt="Homotypic motif combinations"
                  className="w-full rounded-lg border border-slate-200 bg-white"
                />
                <p className="mt-3 text-sm leading-6 text-slate-600">
                  Multiple instances of the <strong>same motif</strong> in one promoter — quantifies co-binding by a single TF family.
                </p>
              </div>
              <div>
                <h4 className="mb-3 text-center font-semibold text-slate-950">Heterotypic</h4>
                <img
                  src="/figures/pmet_heterotypic.png"
                  alt="Heterotypic motif combinations"
                  className="w-full rounded-lg border border-slate-200 bg-white"
                />
                <p className="mt-3 text-sm leading-6 text-slate-600">
                  Pairs of <strong>different motifs</strong> in one promoter — detects cooperation between distinct TFs.
                </p>
              </div>
            </div>
          </details>

          <details className="card group">
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-semibold text-slate-950">
              <span>Mode-specific Pipelines</span>
              <span className="text-slate-400 transition-transform group-open:rotate-180">▾</span>
            </summary>
            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <div>
                <h4 className="mb-3 text-center font-semibold text-slate-950">Promoters Pipeline</h4>
                <img
                  src="/figures/workflow_promoters.png"
                  alt="PMET workflow promoters"
                  className="w-full rounded-lg border border-slate-200 bg-white"
                />
                <p className="mt-3 text-sm leading-6 text-slate-600">
                  Extracts promoter regions from a genome and GFF3 annotation before motif scanning and pairing.
                </p>
              </div>
              <div>
                <h4 className="mb-3 text-center font-semibold text-slate-950">Intervals Pipeline</h4>
                <img
                  src="/figures/workflow_intervals.png"
                  alt="PMET workflow intervals"
                  className="w-full rounded-lg border border-slate-200 bg-white"
                />
                <p className="mt-3 text-sm leading-6 text-slate-600">
                  <strong>Skips promoter extraction</strong> and works directly on user-supplied intervals (e.g. ChIP-seq peaks, ATAC regions).
                </p>
              </div>
            </div>
          </details>
        </div>
      </section>
    </div>
  );
}
