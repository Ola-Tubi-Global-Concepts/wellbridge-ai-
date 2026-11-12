import Link from "next/link";
export default function Footer(){return <footer className="site-footer"><div className="container"><span>© {new Date().getFullYear()} WellBridge AI</span><span>Prototype only · Not an emergency service · <Link href="/privacy">Privacy & safety</Link></span></div></footer>}
