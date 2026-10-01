import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Proxy ke backend ZoBuah di Render. Owner Console tetap dijalankan lokal,
// hanyaPermintaan API yang dialihkan ke produksi lewat proxy dev Vite.
// Dengan begitu browser tidak pernah menyentuh host Render secara langsung,
// sehingga tidak ada CORS yang perlu dikonfigurasi di sisi server.
//
// CATATAN: nama service di render.yaml (fruitpos-api) TIDAK sama dengan host
// yang benar-benar hidup (zobuah). Verifikasi dengan /health sebelum deploy:
//   https://zobuah.onrender.com/health -> {"status":"ok",...}
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": {
        target: "https://zobuah.onrender.com",
        changeOrigin: true,
      },
    },
  },
});
