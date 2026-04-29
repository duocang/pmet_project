'use client';

import { useState, useEffect, useCallback } from 'react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import { taskApi, resultsApi } from '@/lib/api';
import { TaskResponse } from '@/lib/types';
import { useTranslation } from '@/lib/i18n';

const Plot = dynamic(() => import('react-plotly.js'), { ssr: false });

interface PageProps {
  params: { id: string };
}

interface MotifResult {
  cluster: string;
  motif1: string;
  motif2: string;
  gene_num: number;
  total_genes: number;
  cluster_genes: number;
  p_value: number;
  p_adj_bh: number;
  p_adj_bonf: number;
  p_adj_global: number;
  genes: string[];
}

interface ClusterInfo {
  name: string;
  count: number;
}

interface Histogram {
  bin_edges: number[];
  counts: number[];
}

interface Summary {
  total_pairs: number;
  num_clusters: number;
  clusters: ClusterInfo[];
  num_unique_motifs: number;
  significant_pairs_005: number;
  histogram: Histogram;
}

const PAGE_SIZE = 100;

export default function VisualizePage({ params }: PageProps) {
  const { id } = params;
  const { t } = useTranslation();
  const [task, setTask] = useState<TaskResponse | null>(null);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [results, setResults] = useState<MotifResult[]>([]);
  const [totalMatched, setTotalMatched] = useState(0);
  const [selectedCluster, setSelectedCluster] = useState('');
  const [pAdjMax, setPAdjMax] = useState(1.0);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [tableLoading, setTableLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [heatmapResults, setHeatmapResults] = useState<MotifResult[]>([]);

  useEffect(() => {
    const init = async () => {
      try {
        const [taskRes, summaryRes] = await Promise.all([
          taskApi.get(id),
          resultsApi.summary(id),
        ]);
        setTask(taskRes);
        setSummary(summaryRes);

        const heatmapRes = await resultsApi.get(id, { p_adj_max: 0.05, limit: 500 });
        setHeatmapResults(heatmapRes.results);

        const tableRes = await resultsApi.get(id, { limit: PAGE_SIZE, offset: 0 });
        setResults(tableRes.results);
        setTotalMatched(tableRes.total_matched);
      } catch (err: any) {
        console.error('Failed to fetch data:', err);
        if (err?.response?.status === 404) {
          try { setTask(await taskApi.get(id)); } catch { /* ignore */ }
          setError(t('tviz.err.not_ready'));
        } else {
          setError(t('tviz.err.failed'));
        }
      } finally {
        setLoading(false);
      }
    };
    init();
  }, [id, t]);

  const fetchPage = useCallback(async (
    newPage: number,
    cluster?: string,
    maxP?: number,
  ) => {
    setTableLoading(true);
    try {
      const res = await resultsApi.get(id, {
        cluster: cluster || undefined,
        p_adj_max: maxP,
        limit: PAGE_SIZE,
        offset: newPage * PAGE_SIZE,
      });
      setResults(res.results);
      setTotalMatched(res.total_matched);
      setPage(newPage);
    } catch (err) {
      console.error('Failed to fetch results page:', err);
    } finally {
      setTableLoading(false);
    }
  }, [id]);

  const handleFilterChange = (cluster: string, maxP: number) => {
    setSelectedCluster(cluster);
    setPAdjMax(maxP);
    fetchPage(0, cluster, maxP);
  };

  if (loading) {
    return (
      <div className="max-w-6xl mx-auto text-center py-12">{t('tviz.loading')}</div>
    );
  }

  if (!task) {
    return (
      <div className="max-w-6xl mx-auto text-center py-12">
        <p className="text-slate-500">{t('task.not_found')}</p>
      </div>
    );
  }

  const totalPages = Math.ceil(totalMatched / PAGE_SIZE);

  const heatmapData = (() => {
    if (heatmapResults.length === 0) return null;
    const data = selectedCluster
      ? heatmapResults.filter(r => r.cluster === selectedCluster)
      : heatmapResults;
    if (data.length === 0) return null;

    const motifs1 = [...new Set(data.map(r => r.motif1))];
    const motifs2 = [...new Set(data.map(r => r.motif2))];
    const lookup = new Map(data.map(r => [`${r.motif1}|${r.motif2}`, r.p_adj_bh]));

    const z = motifs2.map(m2 =>
      motifs1.map(m1 => {
        const p = lookup.get(`${m1}|${m2}`);
        return p !== undefined ? -Math.log10(Math.max(p, 1e-300)) : 0;
      }),
    );
    return { x: motifs1, y: motifs2, z };
  })();

  return (
    <div className="max-w-6xl mx-auto">
      <div className="flex items-center gap-2 mb-6">
        <Link href={`/tasks/${id}`} className="text-slate-500 hover:text-slate-700">
          {t('tviz.back')}
        </Link>
      </div>

      <h1 className="text-2xl font-bold mb-6">{t('tviz.title')}</h1>

      {error && (
        <div className="card mb-6 text-center py-12 text-slate-500">
          <p>{error}</p>
        </div>
      )}

      {summary && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <div className="card text-center">
              <div className="text-2xl font-bold text-teal-700">{summary.total_pairs.toLocaleString()}</div>
              <div className="text-sm text-slate-500">{t('tviz.stats.total')}</div>
            </div>
            <div className="card text-center">
              <div className="text-2xl font-bold text-teal-700">{summary.num_clusters}</div>
              <div className="text-sm text-slate-500">{t('tviz.stats.clusters')}</div>
            </div>
            <div className="card text-center">
              <div className="text-2xl font-bold text-teal-700">{summary.num_unique_motifs}</div>
              <div className="text-sm text-slate-500">{t('tviz.stats.motifs')}</div>
            </div>
            <div className="card text-center">
              <div className="text-2xl font-bold text-teal-700">{summary.significant_pairs_005.toLocaleString()}</div>
              <div className="text-sm text-slate-500">{t('tviz.stats.sig')}</div>
            </div>
          </div>

          <div className="card mb-6 flex flex-wrap gap-4 items-end">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">{t('tviz.filter.cluster')}</label>
              <select
                className="border rounded px-3 py-1.5 text-sm"
                value={selectedCluster}
                onChange={(e) => handleFilterChange(e.target.value, pAdjMax)}
              >
                <option value="">{t('tviz.filter.cluster_all')}</option>
                {summary.clusters.map(c => (
                  <option key={c.name} value={c.name}>
                    {c.name} ({c.count.toLocaleString()} {t('tviz.filter.cluster_pairs_suffix')})
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">{t('tviz.filter.padj_max')}</label>
              <select
                className="border rounded px-3 py-1.5 text-sm"
                value={pAdjMax}
                onChange={(e) => handleFilterChange(selectedCluster, Number(e.target.value))}
              >
                <option value={1.0}>{t('tviz.filter.padj_all')}</option>
                <option value={0.05}>≤ 0.05</option>
                <option value={0.01}>≤ 0.01</option>
                <option value={0.001}>≤ 0.001</option>
              </select>
            </div>
            <div className="text-sm text-slate-500">
              {totalMatched.toLocaleString()} {t('tviz.matched_pairs_suffix')}
            </div>
          </div>

          {summary.histogram && (
            <div className="card mb-6">
              <h3 className="font-semibold mb-4">{t('tviz.histogram.title')}</h3>
              <div className="h-72">
                <Plot
                  data={[{
                    x: summary.histogram.bin_edges.slice(0, -1).map((e, i) =>
                      (e + summary.histogram.bin_edges[i + 1]) / 2
                    ),
                    y: summary.histogram.counts,
                    type: 'bar' as const,
                    marker: { color: '#0f766e' },
                    width: 1 / summary.histogram.counts.length * 0.9,
                  } as any]}
                  layout={{
                    autosize: true,
                    xaxis: { title: { text: 'Adjusted P-value (BH)' }, range: [0, 1] },
                    yaxis: { title: { text: 'Count' } },
                    margin: { t: 10, r: 10, b: 50, l: 60 },
                    bargap: 0.05,
                  }}
                  config={{ responsive: true, displayModeBar: false }}
                  style={{ width: '100%', height: '100%' }}
                />
              </div>
            </div>
          )}

          <div className="card mb-6">
            <h3 className="font-semibold mb-4">
              {t('tviz.heatmap.title')}
              <span className="text-sm font-normal text-slate-400 ml-2">{t('tviz.heatmap.subtitle')}</span>
            </h3>
            {heatmapData ? (
              <div style={{ height: Math.max(400, heatmapData.y.length * 18 + 120) }}>
                <Plot
                  data={[{
                    z: heatmapData.z,
                    x: heatmapData.x,
                    y: heatmapData.y,
                    type: 'heatmap' as const,
                    colorscale: 'Blues',
                    colorbar: { title: { text: '-log10(p)', side: 'right' as const } },
                  }]}
                  layout={{
                    autosize: true,
                    xaxis: { title: { text: 'Motif 1' }, tickangle: 45, tickfont: { size: 9 } },
                    yaxis: { title: { text: 'Motif 2' }, tickfont: { size: 9 } },
                    margin: { t: 10, r: 10, b: 100, l: 120 },
                  }}
                  config={{ responsive: true }}
                  style={{ width: '100%', height: '100%' }}
                />
              </div>
            ) : (
              <div className="text-center py-8 text-slate-500">{t('tviz.heatmap.empty')}</div>
            )}
          </div>

          <div className="card">
            <h3 className="font-semibold mb-4">
              {t('tviz.table.title_prefix')} ({totalMatched.toLocaleString()} {t('tviz.table.matched_suffix')})
            </h3>
            <div className="overflow-x-auto relative">
              {tableLoading && (
                <div className="absolute inset-0 bg-white/60 flex items-center justify-center z-10">
                  {t('tviz.table.loading')}
                </div>
              )}
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-slate-50">
                    <th className="text-left py-2 px-3">{t('tviz.col.cluster')}</th>
                    <th className="text-left py-2 px-3">{t('tviz.col.motif1')}</th>
                    <th className="text-left py-2 px-3">{t('tviz.col.motif2')}</th>
                    <th className="text-right py-2 px-3">{t('tviz.col.genes')}</th>
                    <th className="text-right py-2 px-3">{t('tviz.col.total')}</th>
                    <th className="text-right py-2 px-3">{t('tviz.col.pvalue')}</th>
                    <th className="text-right py-2 px-3">{t('tviz.col.padj_bh')}</th>
                  </tr>
                </thead>
                <tbody>
                  {results.map((r, i) => (
                    <tr
                      key={`${page}-${i}`}
                      className={`border-b hover:bg-slate-50 ${r.p_adj_bh < 0.05 ? 'bg-teal-50/50' : ''}`}
                    >
                      <td className="py-2 px-3">{r.cluster}</td>
                      <td className="py-2 px-3 font-mono text-xs">{r.motif1}</td>
                      <td className="py-2 px-3 font-mono text-xs">{r.motif2}</td>
                      <td className="py-2 px-3 text-right">{r.gene_num}</td>
                      <td className="py-2 px-3 text-right">{r.total_genes}</td>
                      <td className="py-2 px-3 text-right font-mono text-xs">{r.p_value.toExponential(2)}</td>
                      <td className="py-2 px-3 text-right font-mono text-xs">{r.p_adj_bh.toExponential(2)}</td>
                    </tr>
                  ))}
                  {results.length === 0 && !tableLoading && (
                    <tr>
                      <td colSpan={7} className="py-8 text-center text-slate-500">{t('viz.data.empty')}</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>

            {totalPages > 1 && (
              <div className="flex items-center justify-between mt-4 pt-4 border-t">
                <button
                  className="px-3 py-1 text-sm border rounded hover:bg-slate-50 disabled:opacity-40"
                  disabled={page === 0 || tableLoading}
                  onClick={() => fetchPage(page - 1, selectedCluster, pAdjMax)}
                >
                  {t('viz.page.prev')}
                </button>
                <span className="text-sm text-slate-500">
                  {t('viz.page.page_of_prefix')} {page + 1} {t('viz.page.page_of_mid')} {totalPages.toLocaleString()}
                </span>
                <button
                  className="px-3 py-1 text-sm border rounded hover:bg-slate-50 disabled:opacity-40"
                  disabled={page >= totalPages - 1 || tableLoading}
                  onClick={() => fetchPage(page + 1, selectedCluster, pAdjMax)}
                >
                  {t('viz.page.next')}
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
