export default function DataPage() {
  const species = [
    { name: 'Arabidopsis thaliana', dbs: ['JASPAR Plants 2022', 'PlantTFDB', 'CIS-BP2'] },
    { name: 'Oryza sativa japonica', dbs: ['JASPAR Plants 2022', 'PlantTFDB'] },
    { name: 'Zea mays', dbs: ['JASPAR Plants 2022', 'PlantTFDB'] },
    { name: 'Triticum aestivum', dbs: ['JASPAR Plants 2022'] },
    { name: 'Glycine max', dbs: ['JASPAR Plants 2022'] },
    { name: 'Solanum lycopersicum', dbs: ['JASPAR Plants 2022'] },
  ];

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold mb-6">Pre-computed Data</h1>

      <div className="card mb-6">
        <h2 className="text-lg font-semibold mb-4">Available Species and Motif Databases</h2>
        <p className="text-slate-600 mb-4">
          PMET provides pre-computed homotypic motif hits for 21 plant species
          with multiple transcription factor databases. Using pre-computed data
          significantly reduces analysis time.
        </p>
      </div>

      <div className="grid md:grid-cols-2 gap-4">
        {species.map((s, i) => (
          <div key={i} className="card">
            <h3 className="font-semibold mb-2">{s.name}</h3>
            <div className="flex flex-wrap gap-2">
              {s.dbs.map((db, j) => (
                <span
                  key={j}
                  className="px-2 py-1 bg-primary-100 text-primary-700 rounded text-sm"
                >
                  {db}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div className="card mt-6">
        <h2 className="text-lg font-semibold mb-4">Download Full Dataset</h2>
        <p className="text-slate-600 mb-4">
          The complete pre-computed indexing data can be downloaded from Zenodo:
        </p>
        <a
          href="https://zenodo.org/record/8435321"
          target="_blank"
          rel="noopener noreferrer"
          className="btn-primary inline-block"
        >
          Download from Zenodo
        </a>
      </div>
    </div>
  );
}
