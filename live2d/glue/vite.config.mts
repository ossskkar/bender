import { defineConfig, UserConfig, ConfigEnv } from 'vite';
import path from 'path';

export default defineConfig((env: ConfigEnv): UserConfig => {
  let common: UserConfig = {
    server: {
      port: 5000,
      // Reached from the iPad through `tailscale serve`, which forwards its own
      // Host header. Vite rejects unknown hosts with a bare 403, which looks
      // exactly like a proxy misconfiguration and is not.
      allowedHosts: ['.ts.net'],
    },
    // `vite preview` serves the built dist with no HMR websocket. The dev
    // server's HMR socket cannot reach back through the tailscale proxy, gives
    // up, and reloads the whole page every few seconds -- which reads as a
    // stuttering avatar and makes any frame-rate judgement worthless.
    preview: {
      port: 5001,
      strictPort: true,
      allowedHosts: ['.ts.net'],
    },
    root: './',
    base: '/',
    publicDir: './public',
    resolve: {
      extensions: ['.ts', '.js'],
      alias: {
        '@framework': path.resolve(__dirname, '../../../Framework/src'),
      }
    },
    build: {
      target: 'baseline-widely-available',
      assetsDir: 'assets',
      outDir: './dist',
      sourcemap: env.mode == 'development' ? true : false,
    },
  };
  return common;
});
