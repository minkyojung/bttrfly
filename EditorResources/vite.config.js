// vite.config.js
import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  base: './',
  build: {
    target: 'esnext',
    outDir: 'dist',
    emptyOutDir: true,
    assetsDir: '.',
    rollupOptions: {
      input: resolve(__dirname, 'src/index.js'),   // ← updated entry!
      output: {
        format: 'iife',
        entryFileNames: 'bundle.js',
        inlineDynamicImports: true,
      },
    },
  },
});