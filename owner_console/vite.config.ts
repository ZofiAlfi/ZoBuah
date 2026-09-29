import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Proxy ke backend ZoBuah. Owner Console dan POS menyentuh host yang sama
// saat dev, jadi CORS tidak jadi urusan browser selama pengembangan.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8000",
        changeOrigin: false,
      },
    },
  },
});
