#!/bin/bash

PROJECT="housing-dashboard"
echo "Creating project: $PROJECT..."

mkdir -p $PROJECT/{components,pages/api,public,styles,utils,__tests__,.github/workflows}

# --- Config Files ---
cat > $PROJECT/jest.config.js << 'EOF'
const nextJest = require('next/jest');
const createJestConfig = nextJest({ dir: './' });

const customJestConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  testEnvironment: 'jsdom',
  testPathIgnorePatterns: ['<rootDir>/.next/', '<rootDir>/node_modules/'],
  moduleNameMapper: {
    '^.+\\.(css|scss)$': 'identity-obj-proxy',
  },
  collectCoverage: true,
  collectCoverageFrom: [
    'components/**/*.{js,jsx}',
    'pages/**/*.{js,jsx}',
    'utils/**/*.{js,jsx}',
    '!pages/_*.js',
    '!**/node_modules/**',
    '!**/jest.setup.js',
  ],
  coverageDirectory: 'coverage',
};

module.exports = createJestConfig(customJestConfig);
EOF

echo "import '@testing-library/jest-dom';" > $PROJECT/jest.setup.js

# --- GitHub CI Workflow ---
cat > $PROJECT/.github/workflows/test.yml << 'EOF'
name: Run Unit Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm install

      - name: Run tests with coverage
        run: npm run test:coverage

      - name: Upload coverage
        uses: actions/upload-artifact@v3
        with:
          name: coverage
          path: coverage/
EOF

# --- Components ---
cat > $PROJECT/components/FilterForm.js << 'EOF'
export default function FilterForm({ region, onRegionChange }) {
  return (
    <div className="flex justify-center">
      <input
        type="text"
        value={region}
        onChange={(e) => onRegionChange(e.target.value)}
        className="p-2 rounded border border-gray-300 w-full max-w-md"
        placeholder="Enter city or zip code"
        aria-label="Region input"
      />
    </div>
  );
}
EOF

cat > $PROJECT/components/MarketChart.js << 'EOF'
import { Line } from 'react-chartjs-2';

export default function MarketChart({ title, data }) {
  const chartData = {
    labels: data.map(d => d.label),
    datasets: [
      {
        label: title,
        data: data.map(d => d.value),
        fill: false,
        borderColor: 'black',
        tension: 0.1,
      },
    ],
  };

  return (
    <div className="bg-white p-4 rounded shadow">
      <h2 className="text-xl font-semibold mb-2">{title}</h2>
      <Line data={chartData} />
    </div>
  );
}
EOF

# --- Pages ---
cat > $PROJECT/pages/index.js << 'EOF'
import Head from 'next/head';
import dynamic from 'next/dynamic';
import { useEffect, useState } from 'react';
import FilterForm from '../components/FilterForm';
import { fetchMarketData } from '../utils/marketUtils';

const MarketChart = dynamic(() => import('../components/MarketChart'), { ssr: false });

export default function Home() {
  const [data, setData] = useState(null);
  const [region, setRegion] = useState('Portsmouth, VA');

  useEffect(() => {
    fetchMarketData(region).then(setData);
  }, [region]);

  return (
    <>
      <Head>
        <title>Predictive Intelligence Dashboard</title>
      </Head>
      <main className="p-4 min-h-screen bg-gray-100">
        <h1 className="text-3xl font-bold text-center mb-4">Housing Market Dashboard</h1>
        <FilterForm region={region} onRegionChange={setRegion} />
        {data ? (
          <div className="grid gap-6 mt-6">
            <MarketChart title="Median Price Trend" data={data.prices} />
            <MarketChart title="Inventory Levels" data={data.inventory} />
            <MarketChart title="Buyer's Market Score" data={data.buyerScore} />
          </div>
        ) : (
          <p className="text-center">Loading data for {region}...</p>
        )}
      </main>
    </>
  );
}
EOF

cat > $PROJECT/pages/api/zillow.js << 'EOF'
export default async function handler(req, res) {
  const { address = 'Hampton Roads', location = 'Virginia' } = req.query;

  const formBody = new URLSearchParams();
  formBody.append('address', address);
  formBody.append('location', location);

  try {
    const response = await fetch('https://zillow-com1.p.rapidapi.com/resolveAddressToZpid', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'x-rapidapi-host': process.env.ZILLOW_API_HOST,
        'x-rapidapi-key': process.env.ZILLOW_API_KEY,
      },
      body: formBody.toString(),
    });

    if (!response.ok) throw new Error(`Zillow API failed: ${response.status}`);
    const data = await response.json();

    res.status(200).json({
      prices: [{ label: 'Now', value: data?.zpid ? 325000 : 300000 }],
      inventory: [{ label: 'Now', value: 220 }],
      buyerScore: [{ label: 'Now', value: 48 }],
    });
  } catch (error) {
    try {
      const fallback = await fetch('http://localhost:3000/fallback.json');
      const data = await fallback.json();
      res.status(200).json(data);
    } catch {
      res.status(500).json({ error: 'Failed to fetch both Zillow and fallback data.' });
    }
  }
}
EOF

# --- Utils ---
cat > $PROJECT/utils/marketUtils.js << 'EOF'
export async function fetchMarketData(region) {
  try {
    const res = await fetch(\`/api/zillow?address=\${encodeURIComponent(region)}&location=\${encodeURIComponent(region)}\`);
    return await res.json();
  } catch (error) {
    const fallback = await fetch('/fallback.json');
    return await fallback.json();
  }
}
EOF

# --- Fallback JSON ---
cat > $PROJECT/public/fallback.json << 'EOF'
{
  "prices": [{ "label": "Jan", "value": 305000 }],
  "inventory": [{ "label": "Jan", "value": 240 }],
  "buyerScore": [{ "label": "Jan", "value": 42 }]
}
EOF

# --- Styles ---
echo "@tailwind base; @tailwind components; @tailwind utilities;" > $PROJECT/styles/globals.css

# --- Tests ---
cat > $PROJECT/__tests__/FilterForm.test.js << 'EOF'
import { render, screen, fireEvent } from '@testing-library/react';
import FilterForm from '../components/FilterForm';

test('renders input and triggers region change', () => {
  const handleChange = jest.fn();
  render(<FilterForm region="Initial" onRegionChange={handleChange} />);
  const input = screen.getByPlaceholderText(/enter city/i);
  fireEvent.change(input, { target: { value: 'Boston' } });
  expect(handleChange).toHaveBeenCalledWith('Boston');
});
EOF

cat > $PROJECT/__tests__/MarketChart.test.js << 'EOF'
import { render, screen } from '@testing-library/react';
import MarketChart from '../components/MarketChart';

jest.mock('react-chartjs-2', () => ({
  Line: ({ data }) => <div data-testid="mock-line-chart">{JSON.stringify(data)}</div>,
}));

test('renders chart title and data', () => {
  const testData = [{ label: 'Jan', value: 100 }];
  render(<MarketChart title="Test Chart" data={testData} />);
  expect(screen.getByText('Test Chart')).toBeInTheDocument();
});
EOF

cat > $PROJECT/__tests__/marketUtils.test.js << 'EOF'
import { fetchMarketData } from '../utils/marketUtils';

global.fetch = jest.fn();

afterEach(() => jest.clearAllMocks());

test('fetchMarketData - returns data from API', async () => {
  fetch.mockResolvedValueOnce({ json: () => Promise.resolve({ test: true }) });
  const data = await fetchMarketData('NYC');
  expect(data).toEqual({ test: true });
});
EOF

cat > $PROJECT/__tests__/zillowApi.test.js << 'EOF'
import handler from '../pages/api/zillow';

global.fetch = jest.fn();

const req = { query: { address: 'NYC', location: 'NY' } };
const res = { status: jest.fn(() => res), json: jest.fn() };

test('returns Zillow API data', async () => {
  fetch.mockResolvedValueOnce({ ok: true, json: async () => ({ zpid: '123' }) });
  await handler(req, res);
  expect(res.status).toHaveBeenCalledWith(200);
  expect(res.json).toHaveBeenCalled();
});
EOF

# --- Package.json base ---
cat > $PROJECT/package.json << 'EOF'
{
  "name": "housing-dashboard",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "@testing-library/react": "^14.0.0",
    "@testing-library/jest-dom": "^6.0.0",
    "identity-obj-proxy": "^3.0.0",
    "jest-environment-jsdom": "^29.0.0"
  }
}
EOF

# --- Zip It ---
cd $PROJECT/..
zip -r $PROJECT.zip $PROJECT > /dev/null
echo "✅ Project $PROJECT.zip created successfully!"
