module.exports = {
  apps: [
    {
      name: 'opspika-process-exporter',
      script: '__EXPORTER_DIR__/server.js',
      cwd: '__EXPORTER_DIR__',
      interpreter: '__NODE_BINARY__',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '128M',
      env: {
        PM2_BINARY: '__PM2_BINARY__',
        PM2_EXPORTER_PROCESS_NAME: 'opspika-process-exporter',
        PM2_EXPORTER_HOST: '127.0.0.1',
        PM2_EXPORTER_PORT: '9988',
        PM2_EXPORTER_INTERVAL_MS: '5000',
        PM2_EXPORTER_COMMAND_TIMEOUT_MS: '5000',
      },
    },
  ],
};
