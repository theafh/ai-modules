import { defineConfig } from "vite"
import { gui } from "@opencode/plugin/gui/vite"

export default defineConfig({
  plugins: [gui({ outFile: "dist/gui.cjs" })],
})
