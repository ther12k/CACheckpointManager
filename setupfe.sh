echo "Attempting to create Tauri project '$PROJECT_NAME' with template '$FRONTEND_TEMPLATE' using pnpm..."
echo "Please follow ALL interactive prompts from 'pnpm create tauri-app'."
echo "-> When asked for 'App name', use: $PROJECT_NAME"
echo "-> When asked for 'Window title', use: Checkpoint Manager"
echo "-> When asked to 'Choose your UI template', select: $FRONTEND_TEMPLATE"
echo "-> When asked for 'package manager', select: pnpm"
echo

# if pnpm create tauri-app; then
#     echo -e "\nSUCCESS: Tauri project scaffolding initiated with pnpm.\n"
# else
#     echo -e "\n---------------------------------------------------------------------"
#     echo "ERROR: 'pnpm create tauri-app' failed or was cancelled."
#     echo "Ensure Node.js, pnpm, Rust, and Tauri v2 prerequisites are installed."
#     echo "Prerequisites: https://v2.tauri.app/start/prerequisites/"
#     echo "---------------------------------------------------------------------"
#     exit 1
# fi

# echo "IMPORTANT: 'pnpm create tauri-app' likely created a new directory for your project."
# echo "Please enter the exact name of the directory that was just created (usually '$PROJECT_NAME')."
read -p "Enter the project directory name: " ACTUAL_PROJECT_DIR

if [ -z "$ACTUAL_PROJECT_DIR" ]; then
    echo "No project directory name entered. Exiting."
    exit 1
fi
# if [ ! -d "$ACTUAL_PROJECT_DIR" ]; then
#     echo "ERROR: Directory '$ACTUAL_PROJECT_DIR' not found. Exiting."
#     exit 1
# fi

# # cd "$ACTUAL_PROJECT_DIR" || { echo "ERROR: Failed to cd into '$ACTUAL_PROJECT_DIR'."; exit 1; }
# # echo "Changed directory to $(pwd)"
# # echo

if [ ! -d "src-tauri" ]; then
    echo "ERROR: 'src-tauri' directory not found. Initialization incomplete. Exiting."
    exit 1
fi

# 2. Install Tailwind CSS v4 (following official shadcn Vite guide)
echo "Installing Tailwind CSS v4..."
pnpm add tailwindcss @tailwindcss/vite

# 3. Create/update src/index.css with Tailwind v4 import and create temporary config
echo "Setting up Tailwind CSS v4..."
CSS_FILE_PATH="src/index.css"

# Ensure src directory exists
mkdir -p src

if [ -f "$CSS_FILE_PATH" ]; then
    # Backup existing CSS
    cp "$CSS_FILE_PATH" "${CSS_FILE_PATH}.backup"
    echo "Backed up existing CSS to ${CSS_FILE_PATH}.backup"
fi

# Replace everything in src/index.css with Tailwind import (as per official guide)
cat > "$CSS_FILE_PATH" << 'EOF'
@import "tailwindcss";
EOF

echo "Created/updated $CSS_FILE_PATH with Tailwind v4 import directive."

# Create a temporary tailwind.config.js for shadcn/ui compatibility
# This will be removed after shadcn/ui setup is complete
echo "Creating temporary Tailwind config for shadcn/ui compatibility..."
cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF
echo "Created temporary tailwind.config.js (will be removed after shadcn/ui setup)"

# 4. Install @types/node for path resolution
echo "Installing @types/node for path resolution..."
pnpm add -D @types/node

# 5. Update vite.config.ts (following official shadcn Vite guide)
echo "Updating vite.config.ts..."
VITE_CONFIG_PATH="vite.config.ts"

cat > $VITE_CONFIG_PATH << 'EOF'
import path from "path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;

// https://vite.dev/config/
export default defineConfig(async () => ({
  plugins: [
    react(),
    tailwindcss(),
  ],
  
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
EOF
echo "Vite configuration updated with Tailwind CSS v4 and path aliases."

# 6. Update TypeScript configuration (following official shadcn Vite guide)
echo "Updating TypeScript configuration for path aliases..."

# Update tsconfig.json
if [ -f "tsconfig.json" ]; then
    cp tsconfig.json tsconfig.json.backup
    echo "Backed up tsconfig.json"
    
    cat > tsconfig.json << 'EOF'
{
  "files": [],
  "references": [
    {
      "path": "./tsconfig.app.json"
    },
    {
      "path": "./tsconfig.node.json"
    }
  ],
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
EOF
    echo "Updated tsconfig.json with path aliases."
else
    echo "WARNING: tsconfig.json not found."
fi

# Update tsconfig.app.json (if it exists - Vite splits config)
if [ -f "tsconfig.app.json" ]; then
    cp tsconfig.app.json tsconfig.app.json.backup
    echo "Backed up tsconfig.app.json"
    
    # Read existing tsconfig.app.json and add baseUrl and paths
    cat > tsconfig_app_temp.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"]
}
EOF
    mv tsconfig_app_temp.json tsconfig.app.json
    echo "Updated tsconfig.app.json with path aliases."
fi

# 7. Run shadcn/ui init (following official guide)
echo ""
echo "---------------------------------------------------------------------"
echo "Running shadcn/ui initialization..."
echo "This step is INTERACTIVE. Please answer the prompts."
echo "Recommended answers:"
echo "  - Which color would you like to use as base color? › Neutral (or your preference)"
echo "  - Other prompts: Accept defaults or customize as needed"
echo "---------------------------------------------------------------------"
echo "Running: pnpm dlx shadcn@latest init"
if pnpm dlx shadcn@latest init; then
    echo -e "\n✅ shadcn/ui initialized successfully.\n"
else
    echo -e "\n⚠️  shadcn/ui initialization failed or was cancelled."
    echo "You can run 'pnpm dlx shadcn@latest init' manually later."
    echo ""
fi
# 8. Install essential shadcn/ui components
echo ""
echo "---------------------------------------------------------------------"
echo "Installing essential shadcn/ui components..."
echo "This will install commonly used components for your app."
echo "---------------------------------------------------------------------"

# Install core components that are commonly needed
COMPONENTS_TO_INSTALL="button card input label textarea select dialog alert-dialog dropdown-menu separator badge avatar"

for component in $COMPONENTS_TO_INSTALL; do
    echo "Installing $component component..."
    if pnpm dlx shadcn@latest add $component --yes; then
        echo "✅ $component installed successfully"
    else
        echo "⚠️  Failed to install $component (you can install it manually later)"
    fi
done

# 9. Clean up temporary config and finalize Tailwind v4 setup
echo ""
echo "Finalizing Tailwind CSS v4 setup..."
if [ -f "tailwind.config.js" ]; then
    rm tailwind.config.js
    echo "Removed temporary tailwind.config.js"
fi

# Update src/index.css to include any custom configurations if needed
echo "Tailwind CSS v4 is now properly configured with CSS-based configuration."
echo "You can add custom themes and configurations directly in src/index.css using @theme directive."

echo ""
echo "---------------------------------------------------------------------"
echo "✅ Setup completed successfully!"
echo ""
echo "Tailwind CSS v4 has been configured:"
echo "  - Installed: tailwindcss @tailwindcss/vite"
echo "  - CSS import directive added to src/index.css"
echo "  - Vite plugin integration with path aliases"
echo ""
echo "Shadcn/UI has been set up:"
echo "  - Interactive initialization completed"
echo "  - Essential components installed: $COMPONENTS_TO_INSTALL"
echo "  - TypeScript path aliases configured"
echo ""
echo "To add more shadcn/ui components, use:"
echo "  pnpm dlx shadcn@latest add [component-name]"
echo ""
echo "Available components: https://ui.shadcn.com/docs/components"
echo ""
echo "Example usage in your components:"
echo "  import { Button } from '@/components/ui/button'"
echo "  import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'"
echo ""
echo "You can now start development with: pnpm tauri dev"
echo "---------------------------------------------------------------------"