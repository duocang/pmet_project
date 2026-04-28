# PMET Frontend

Next.js-based frontend for the PMET web application.

## Quick Start

```bash
# Install dependencies
npm install

# Development
npm run dev

# Production build
npm run build
npm start
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| NEXT_PUBLIC_API_URL | http://localhost:8000 | Backend API URL |

## Pages

- `/` - Home page with analysis mode selection
- `/submit` - Submit new analysis task
- `/tasks` - List user tasks
- `/tasks/[id]` - Task detail and status
- `/tasks/[id]/visualize` - Results visualization
- `/data` - Pre-computed data information
- `/about` - About PMET

## Docker

```bash
docker build -t pmet-frontend .
docker run -p 3000:3000 -e NEXT_PUBLIC_API_URL=http://api:8000 pmet-frontend
```

## Tech Stack

- Next.js 14
- React 18
- TypeScript
- Tailwind CSS
- Plotly.js (visualizations)
- Zustand (state management)
- React Dropzone (file uploads)
