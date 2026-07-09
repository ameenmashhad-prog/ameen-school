import './globals.css';

export const metadata = {
  title: 'Amin Forms Studio v3',
  description: 'محرك الاستمارات والتقارير ثلاثي اللغة'
};

export default function RootLayout({ children }) {
  return (
    <html lang="ar" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
