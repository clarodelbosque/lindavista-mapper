import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// The panel ships inside the app bundle as one self-contained index.html (scripts and
// styles inlined), loaded by WKWebView from a file URL. `npm run dev` serves it with hot
// reload for `LindaVistaMapper --ui-dev-url http://localhost:5173`.
export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile()],
  resolve: {
    alias: { '@': path.resolve(import.meta.dirname, './src') },
  },
})
