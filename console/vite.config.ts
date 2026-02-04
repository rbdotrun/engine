/// <reference types="vitest/config" />
import { defineConfig, Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "path";

// Plugin to inject CSS into JS bundle
function cssInjectionPlugin(): Plugin {
  return {
    name: "css-injection",
    apply: "build",
    enforce: "post",
    generateBundle(_, bundle) {
      let cssContent = "";
      const cssFiles: string[] = [];

      // Collect all CSS
      for (const [fileName, chunk] of Object.entries(bundle)) {
        if (fileName.endsWith(".css") && chunk.type === "asset") {
          cssContent += chunk.source;
          cssFiles.push(fileName);
        }
      }

      // Remove CSS files from bundle
      for (const file of cssFiles) {
        delete bundle[file];
      }

      // Inject CSS into JS
      if (cssContent) {
        for (const [_, chunk] of Object.entries(bundle)) {
          if (chunk.type === "chunk" && chunk.isEntry) {
            const cssInjection = `(function(){var s=document.createElement('style');s.textContent=${JSON.stringify(cssContent)};document.head.appendChild(s);})();`;
            chunk.code = cssInjection + chunk.code;
          }
        }
      }
    },
  };
}

export default defineConfig(({ mode, command }) => ({
  plugins: [
    react(),
    tailwindcss(),
    ...(command === "build" ? [cssInjectionPlugin()] : []),
  ],
  define:
    mode === "test"
      ? {}
      : command === "serve"
        ? {}
        : {
            "process.env.NODE_ENV": JSON.stringify("production"),
            "process.env": {},
          },
  // Build config - only applies during `vite build`
  build: {
    lib: {
      entry: resolve(__dirname, "src/index.tsx"),
      name: "RbrunConsole",
      formats: ["iife"],
      fileName: () => "console.js",
    },
    outDir: "../app/javascript/rbrun",
    emptyOutDir: true,
    cssCodeSplit: false,
    manifest: true,
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
      },
    },
  },
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts",
  },
}));
