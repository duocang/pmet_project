export default function AboutPage() {
  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">About PMET</h1>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">What is PMET?</h2>
        <p className="text-slate-600 mb-4">
          PMET (Promoter Motif Enrichment Tool) identifies cooperative transcription
          factor (TF) activity by evaluating both homotypic and heterotypic motif
          combinations across promoter sets.
        </p>
        <ul className="list-disc list-inside text-slate-600 space-y-2">
          <li>
            Scores combinations of motifs within transcriptional regulatory modules
            to reveal TF cooperation
          </li>
          <li>
            Handles homotypic and heterotypic motifs simultaneously, avoiding biases
            from single-motif analyses
          </li>
          <li>
            Provides multiple engines: C, C++ (feature-rich), and a fused build that
            integrates FIMO scanning
          </li>
          <li>
            Offers original and parallel pairing (downstream enrichment) for
            performance scaling
          </li>
        </ul>
      </div>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">How to Cite</h2>
        <p className="text-slate-600">
          If you use PMET in your research, please cite:
        </p>
        <blockquote className="border-l-4 border-primary-500 pl-4 mt-4 text-slate-600 italic">
          PMET: Promoter Motif Enrichment Tool for identifying cooperative
          transcription factor activity.
        </blockquote>
      </div>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">Resources</h2>
        <ul className="space-y-2">
          <li>
            <a
              href="https://github.com/duocang/PMET_project"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-700 hover:underline"
            >
              GitHub Repository →
            </a>
          </li>
          <li>
            <a
              href="http://pmet.online"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-700 hover:underline"
            >
              PMET Online →
            </a>
          </li>
        </ul>
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Analysis Modes</h2>

        <div className="space-y-4">
          <div>
            <h3 className="font-medium text-slate-900">Pre-computed Promoters</h3>
            <p className="text-slate-600 text-sm">
              Use our pre-computed motif databases for 21 plant species. Fastest option
              when your species and motif database are available.
            </p>
          </div>

          <div>
            <h3 className="font-medium text-slate-900">Full Promoters</h3>
            <p className="text-slate-600 text-sm">
              Upload your own genome, annotation (GFF3), and motif database (MEME format)
              for custom analysis. Most flexible option.
            </p>
          </div>

          <div>
            <h3 className="font-medium text-slate-900">Intervals</h3>
            <p className="text-slate-600 text-sm">
              Analyze custom genomic intervals (e.g., ChIP-seq peaks) with a motif database.
              Suitable for non-promoter analyses.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
