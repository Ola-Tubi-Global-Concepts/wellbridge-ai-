import Link from "next/link";
export default function Header(){return <header className="site-header"><div className="header-inner"><Link className="brand" href="/">WellBridge <span>AI</span></Link><nav><Link href="/check-in">Wellbeing check-in</Link><Link href="/directory">Care pathways</Link><Link href="/privacy">Privacy & safety</Link></nav></div></header>}
