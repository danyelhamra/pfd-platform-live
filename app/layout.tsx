import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";
import AuthProvider from "./auth-provider";

export const metadata: Metadata = {
  title: "PFD | Player Focused Development",
  description:
    "Put player development at the centre. Connect assessments, training, homework and coach feedback.",

  icons: {
    icon: "/pfd-icon.png",
    apple: "/pfd-icon.png",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
