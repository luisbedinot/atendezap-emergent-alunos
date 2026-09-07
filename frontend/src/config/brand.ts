// Branding centralizado. Troque aqui pra renomear/recolorir o app inteiro.
export const brand = {
  name: "AtendeZap",
  tagline: "IA que atende seu WhatsApp 24/7 + CRM Kanban",
  // WhatsApp green
  primary: "#22C55E",
  primaryOklch: "0.72 0.18 152",
};

// Cada clone configura o próprio suporte sem herdar o número do projeto original.
export const supportWhatsapp = String(import.meta.env.VITE_SUPPORT_WHATSAPP || "").replace(/\D/g, "");
export const supportConfigured = supportWhatsapp.length >= 10;
export const supportWhatsappUrl = supportConfigured ? `https://wa.me/${supportWhatsapp}` : "/";
export const supportWhatsappDisplay = supportConfigured
  ? String(import.meta.env.VITE_SUPPORT_WHATSAPP_DISPLAY || supportWhatsapp)
  : "";
