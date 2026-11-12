import Link from "next/link";

export default function HomePage() {
  return <div className="container">
    <section className="hero">
      <p className="eyebrow">WELLBRIDGE AI</p>
      <h1>Earlier Support.<br /><span>Trusted Care.</span></h1>
      <p className="lead">A clearer path to wellbeing information, supportive next steps and trusted care pathways.</p>
      <div className="actions"><Link className="button" href="/check-in">Explore a wellbeing check-in</Link><Link className="button secondary" href="/directory">Explore care navigation</Link></div>
    </section>
    <section className="notice"><strong>Prototype notice</strong><p>WellBridge AI is not a live healthcare service. It does not diagnose, prescribe, dispatch emergency help or confirm referrals. Please do not submit real medical or personal health information.</p></section>
    <section className="cards">
      <article className="card"><h2>Understand wellbeing</h2><p>Explore general wellbeing information and optional reflection prompts. This is not a clinical assessment.</p></article>
      <article className="card"><h2>Explore support options</h2><p>Learn how self-help, community support, primary care and specialist services can fit into a stepped-care pathway.</p></article>
      <article className="card"><h2>Human-led care</h2><p>Real-world referrals and crisis response require verified services and accountable human teams.</p></article>
    </section>
  </div>;
}
