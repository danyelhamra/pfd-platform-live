import Image from "next/image";
import AccountMenu from "./account-menu";

const features = [
  {
    number: "01",
    tag: "ASSESSMENTS & REPORTS",
    title: "See the player clearly.",
    description:
      "Bring coach assessments and player self-reflection together. Understand strengths, identify areas to improve and give development a starting point.",
  },
  {
    number: "02",
    tag: "TRAINING PLANS",
    title: "Give every session purpose.",
    description:
      "Build training plans from reusable exercises and templates. Connect the work on the pitch to what your players need.",
  },
  {
    number: "03",
    tag: "HOMEWORK & FEEDBACK",
    title: "Keep developing off the pitch.",
    description:
      "Assign work to individuals or the whole team. Players upload their practice, and coaches give feedback they can put into action.",
  },
  {
    number: "04",
    tag: "YOUR TEAM, CONNECTED",
    title: "Move forward together.",
    description:
      "Keep training, games and announcements in one shared space, so players know what is happening and what comes next.",
  },
];
const steps = [
  {
    title: "Assess",
    description:
      "Understand the player through coach reports and self-assessment.",
  },
  {
    title: "Plan",
    description:
      "Identify priorities and build purposeful training around them.",
  },
  {
    title: "Practise",
    description:
      "Put development into action through training and individual homework.",
  },
  {
    title: "Review",
    description: "Give feedback, revisit reports and guide the next steps.",
  },
];

export default function Home() {
  return (
    <>
      <a href="#main-content" className="skip-link">
        Skip to content
      </a>
      <header id="top" className="site-header">
        <div className="container header-inner">
          <a href="#top" aria-label="PFD home" className="wordmark">
            PFD<span>.</span>
          </a>
          <nav aria-label="Main navigation">
            <a href="#features">The platform</a>
            <a href="#how-it-works">How it works</a>
          </nav>
          <AccountMenu />
        </div>
      </header>
      <main id="main-content">
        <section className="hero container">
          <div className="hero-copy">
            <p className="eyebrow">
              <span className="small-line" />
              PLAYER FOCUSED DEVELOPMENT
            </p>
            <h1>
              Put the player.
              <br />
              <span>At the centre.</span>
            </h1>
            <p className="hero-description">
              Give every player a clearer direction. Connect assessments,
              training, homework and feedback—so coaches can guide development
              and players can take ownership of it.
            </p>
            <div className="hero-actions">
              <a href="#features" className="button primary">
                Explore the platform <span aria-hidden="true">↗</span>
              </a>
              <a href="#how-it-works" className="text-link">
                How it works <span aria-hidden="true">↓</span>
              </a>
            </div>
            <p className="hero-footnote">
              FOR PLAYERS. WITH COACHES. THROUGH CLUBS.
            </p>
          </div>
          <figure className="hero-figure">
            <div className="hero-image">
              <Image
                src="/pfd-football.png"
                alt="Football players practising a passing drill on a grass pitch"
                fill
                sizes="(min-width: 1240px) 560px, (min-width: 900px) 48vw, 100vw"
                className="football-image"
              />
            </div>
            <figcaption>
              <span className="caption-dot" /> DEVELOPMENT STARTS WITH THE
              PLAYER.<span aria-hidden="true">↗</span>
            </figcaption>
          </figure>
        </section>
        <div className="container">
          <div className="principles">
            {[
              "Understand the individual.",
              "Give practice a purpose.",
              "Make feedback count.",
            ].map((text) => (
              <p key={text}>
                <span aria-hidden="true">↗</span>
                {text}
              </p>
            ))}
          </div>
        </div>
        <section id="features" className="features-section">
          <div className="container">
            <div className="section-heading">
              <div>
                <p className="eyebrow">THE PLATFORM</p>
                <h2>
                  A connected approach
                  <br />
                  to player development.
                </h2>
              </div>
              <p>
                From the first assessment to the next training session, keep the
                work focused on helping players develop.
              </p>
            </div>
            <div className="feature-grid">
              {features.map((feature) => (
                <article className="feature-card" key={feature.number}>
                  <div className="card-meta">
                    <span>{feature.number}</span>
                    <span>{feature.tag}</span>
                  </div>
                  <h3>{feature.title}</h3>
                  <p>{feature.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>
        <section id="how-it-works" className="journey-section container">
          <p className="eyebrow">HOW IT WORKS</p>
          <h2>Give development direction.</h2>
          <div className="journey-grid">
            {steps.map((step, index) => (
              <article key={step.title}>
                <span className="step-number">0{index + 1}</span>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </article>
            ))}
          </div>
        </section>
        <section className="people-section">
          <div className="container people-grid">
            <div>
              <p className="eyebrow">A SHARED RESPONSIBILITY</p>
              <h2>
                Guided by coaches.
                <br />
                <span>Owned by players.</span>
              </h2>
            </div>
            <div className="audiences">
              {[
                [
                  "For coaches",
                  "Understand your players, organise their development and give feedback they can put into practice.",
                ],
                [
                  "For players",
                  "Reflect on your game, understand what to work on and stay connected to your development.",
                ],
                [
                  "For clubs",
                  "Support a consistent approach to player development across your coaches and teams.",
                ],
              ].map(([title, description]) => (
                <article key={title}>
                  <h3>{title}</h3>
                  <p>{description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>
      </main>
      <footer className="container footer">
        <a href="#top" className="wordmark" aria-label="PFD home">
          PFD<span>.</span>
        </a>
        <p>Player Focused Development</p>
        <a href="#top" className="back-top">
          Back to top ↑
        </a>
      </footer>
    </>
  );
}
