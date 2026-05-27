const path = require("node:path");

const rootDir = __dirname;

module.exports = {
  apps: [
    {
      name: "monitoring-backend",
      cwd: path.join(rootDir, "backend"),
      script: "node",
      args: "dist/main.js",
      env: { NODE_ENV: "production" },
    },
    {
      name: "monitoring-web",
      cwd: path.join(rootDir, "web"),
      script: "npm",
      args: "run preview -- --host 0.0.0.0 --port 4173",
      env: { NODE_ENV: "production" },
    },
  ],
};
