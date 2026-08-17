import { useMemo, useState } from 'react';
import {
  ArrowRight,
  Braces,
  Check,
  Clipboard,
  Database,
  GitBranch,
  Globe2,
  Mail,
  Rocket,
  ShieldCheck,
  ShoppingCart,
  Terminal,
} from 'lucide-react';

const actorRef = 'fluting_frostfield~url-intelligence-api';
const deployedUrl = 'https://apify-api-portfolio-factory.netlify.app';

const sampleOutput = {
  url: 'https://example.com',
  status: 'ok',
  httpStatus: 200,
  title: 'Example Domain',
  wordCount: 17,
  linkCount: 1,
  technologies: [],
};

const workflow = [
  ['Visitor lands here', 'The website explains the API, shows proof, and makes the use case obvious in seconds.'],
  ['Buyer clicks Apify', 'The primary CTA sends qualified users to the Actor page where they can run the API.'],
  ['Usage is metered', 'Apify handles execution, logs, datasets, and usage-based product delivery.'],
  ['You improve winners', 'Keep the Actor reliable and clone the same website-plus-Actor funnel into related APIs.'],
];

const proofItems = [
  ['Permission test', 'Auth, Actor create/delete, and KV read/write/delete passed.'],
  ['Cloud build', 'Private Actor version 0.2 built successfully on Apify.'],
  ['Smoke test', 'Live run returned one valid dataset item for example.com.'],
];

const incomeSteps = [
  ['Traffic arrives', 'Search, posts, docs, GitHub, and Apify discovery send users to this page. The page explains one paid outcome: URL intelligence without custom scraping code.'],
  ['Visitors convert', 'The website pushes two actions: run the Actor on Apify or submit the buyer form for managed access, integrations, or bulk usage.'],
  ['The product delivers itself', 'Customers run the Actor in Apify. The API produces dataset rows automatically, so you do not manually fulfill each order.'],
  ['Revenue compounds', 'After marketplace monetization and payout setup are enabled, usage can create recurring revenue while the same funnel is cloned for more Actors.'],
];

export function App() {
  const [url, setUrl] = useState('https://example.com');
  const [copied, setCopied] = useState(false);
  const [mode, setMode] = useState<'curl' | 'json'>('curl');

  const command = useMemo(() => {
    const input = JSON.stringify({
      urls: [url],
      maxLinksPerUrl: 5,
      timeoutMs: 12000,
      includeTextSample: false,
    }, null, 2);

    if (mode === 'json') return input;

    return `curl -X POST "https://api.apify.com/v2/acts/${actorRef}/run-sync-get-dataset-items" \\\n  -H "Authorization: Bearer $APIFY_TOKEN" \\\n  -H "Content-Type: application/json" \\\n  -d '${input.replaceAll('\n', '')}'`;
  }, [mode, url]);

  async function copyCommand() {
    await navigator.clipboard.writeText(command);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="URL Intelligence API home">
          <span className="brand-mark"><Braces size={22} /></span>
          <span>URL Intelligence API</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#product">Product</a>
          <a href="#output">Output</a>
          <a href="#income">Income</a>
          <a href="#pricing">Pricing</a>
        </nav>
        <a className="header-action" href={`https://console.apify.com/actors/${actorRef}`} target="_blank" rel="noreferrer">
          Buy API access
          <ArrowRight size={16} />
        </a>
      </header>

      <section id="top" className="hero">
        <div className="hero-copy">
          <h1>Sell URL intelligence while the API runs itself.</h1>
          <p>
            A live Apify Actor turns public URLs into metadata, links, text statistics, contact hints, and technology signals. This page is the sales funnel that sends buyers to run it.
          </p>
          <div className="hero-actions">
            <a className="primary-action" href={`https://console.apify.com/actors/${actorRef}`} target="_blank" rel="noreferrer">
              <ShoppingCart size={18} />
              Buy API access
            </a>
            <a className="secondary-action" href="#lead-form">
              Request managed access
              <ArrowRight size={17} />
            </a>
          </div>
          <div className="status-strip" aria-label="Deployment status">
            <span><Check size={16} />Actor {actorRef}</span>
            <span><Check size={16} />Build succeeded</span>
            <span><Check size={16} />Smoke test passed</span>
          </div>
        </div>

        <div className="hero-panel" aria-label="Sample output">
          <div className="panel-topbar">
            <span>dataset-item.json</span>
            <span>live schema</span>
          </div>
          <pre>{JSON.stringify(sampleOutput, null, 2)}</pre>
        </div>
      </section>

      <section id="product" className="split-band">
        <div>
          <h2>A focused API Actor, not a generic scraper.</h2>
          <p>
            URL Intelligence API is a small paid utility for lead enrichment, SEO triage, AI-agent preprocessing, and competitive research pipelines that need predictable rows instead of raw HTML.
          </p>
        </div>
        <div className="feature-list">
          <Feature icon={<Globe2 />} title="Public URL input" text="Validated HTTP and HTTPS URLs with conservative timeout controls." />
          <Feature icon={<Database />} title="Dataset-ready output" text="Stable fields for status, title, links, word counts, and technology hints." />
          <Feature icon={<ShieldCheck />} title="Built to sell" text="A narrow promise, working proof, pricing copy, and buyer capture are all on this page." />
        </div>
      </section>

      <section id="demo" className="demo-section">
        <div className="section-heading">
          <h2>Try the request shape before you run it.</h2>
          <p>Change the URL and copy either the cURL command or JSON body.</p>
        </div>
        <div className="demo-grid">
          <div className="request-builder">
            <label htmlFor="url">URL</label>
            <input id="url" value={url} onChange={(event) => setUrl(event.target.value)} />
            <div className="segmented" role="tablist" aria-label="Request format">
              <button className={mode === 'curl' ? 'active' : ''} onClick={() => setMode('curl')} type="button">cURL</button>
              <button className={mode === 'json' ? 'active' : ''} onClick={() => setMode('json')} type="button">JSON</button>
            </div>
            <button className="copy-button" onClick={copyCommand} type="button">
              <Clipboard size={17} />
              {copied ? 'Copied' : 'Copy request'}
            </button>
          </div>
          <pre className="command-block">{command}</pre>
        </div>
      </section>

      <section id="output" className="schema-section">
        <div className="section-heading">
          <h2>Output designed for downstream automation.</h2>
          <p>Every run returns normalized dataset items that can be consumed by agents, dashboards, enrichment jobs, and customer-facing APIs.</p>
        </div>
        <div className="schema-grid">
          {['url', 'status', 'httpStatus', 'title', 'description', 'canonicalUrl', 'wordCount', 'linkCount', 'emails', 'technologies', 'links', 'fetchedAt'].map((field) => (
            <span key={field}>{field}</span>
          ))}
        </div>
      </section>

      <section className="workflow-section">
        <div className="section-heading">
          <h2>The website is the acquisition machine.</h2>
          <p>The Actor does the work. The website explains the value, captures demand, and sends users to the paid run path.</p>
        </div>
        <div className="timeline">
          {workflow.map(([title, text], index) => (
            <div className="timeline-item" key={title}>
              <span>{String(index + 1).padStart(2, '0')}</span>
              <h3>{title}</h3>
              <p>{text}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="deploy" className="proof-section">
        <div>
          <h2>Deployment proof is part of the product.</h2>
          <p>
            The Actor was built and tested through Apify’s API, and this public site is shipped through Netlify with the URL stored in the GitHub-facing project documentation.
          </p>
          <a className="secondary-action dark" href={deployedUrl}>
            <Rocket size={17} />
            Netlify deployment
          </a>
        </div>
        <div className="proof-list">
          {proofItems.map(([title, text]) => (
            <div className="proof-row" key={title}>
              <Check size={18} />
              <div>
                <strong>{title}</strong>
                <p>{text}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="income-section" id="income">
        <div className="section-heading">
          <h2>How the website is meant to make passive income.</h2>
          <p>
            It works as a public storefront for a small API product: visitors find the page, understand the offer, click to run the Actor, or submit a buyer request.
          </p>
        </div>
        <div className="income-grid">
          {incomeSteps.map(([title, text], index) => (
            <article className="income-card" key={title}>
              <span>{String(index + 1).padStart(2, '0')}</span>
              <h3>{title}</h3>
              <p>{text}</p>
            </article>
          ))}
        </div>
        <div className="income-note">
          <strong>Realistic expectation:</strong>
          <p>
            The website can sell and capture buyers 24/7, but real revenue still requires traffic plus enabled Apify monetization or a payment/contract path for captured leads.
          </p>
        </div>
      </section>

      <section id="pricing" className="pricing-section">
        <div className="pricing-copy">
          <h2>Pricing designed for a small API product.</h2>
          <p>
            The page sells the outcome, not the code: clean URL intelligence for teams that do not want to build and maintain their own scraper.
          </p>
        </div>
        <div className="pricing-panel">
          <div><ShoppingCart size={18} /> Buy on Apify</div>
          <div><Mail size={18} /> Capture high-intent leads</div>
          <div><GitBranch size={18} /> Portfolio cloning</div>
          <div><Terminal size={18} /> CI deployment</div>
        </div>
      </section>

      <section className="lead-section" id="lead-form">
        <div>
          <h2>Capture buyers who need more than a one-off run.</h2>
          <p>
            Some visitors will want volume runs, integrations, or managed delivery. This Netlify form turns those visitors into leads you can close separately.
          </p>
        </div>
        <form name="api-leads" method="POST" data-netlify="true" netlify-honeypot="bot-field" className="lead-form">
          <input type="hidden" name="form-name" value="api-leads" />
          <p className="hidden-field">
            <label>Do not fill this out: <input name="bot-field" /></label>
          </p>
          <label htmlFor="lead-name">Name</label>
          <input id="lead-name" name="name" autoComplete="name" required />
          <label htmlFor="lead-email">Email</label>
          <input id="lead-email" name="email" type="email" autoComplete="email" required />
          <label htmlFor="lead-company">Company</label>
          <input id="lead-company" name="company" autoComplete="organization" />
          <label htmlFor="lead-use-case">Use case</label>
          <input id="lead-use-case" name="useCase" placeholder="Lead enrichment, SEO audit, AI agent preprocessing..." />
          <label htmlFor="lead-message">Message</label>
          <textarea id="lead-message" name="message" rows={4} placeholder="Tell me how many URLs you need processed and how often." />
          <button className="copy-button" type="submit">
            <Mail size={17} />
            Request API access
          </button>
        </form>
      </section>

      <footer>
        <span>URL Intelligence API</span>
        <span>Actor: {actorRef}</span>
        <span>Netlify: {deployedUrl}</span>
      </footer>
    </main>
  );
}

function Feature({ icon, title, text }: { icon: React.ReactNode; title: string; text: string }) {
  return (
    <article className="feature">
      <div className="feature-icon">{icon}</div>
      <div>
        <h3>{title}</h3>
        <p>{text}</p>
      </div>
    </article>
  );
}
