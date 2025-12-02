/**
 * Windows Service Wrapper for RetailPOS Print Helper
 * This script installs/uninstalls the print server as a Windows Service
 */

import { Service } from 'node-windows';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create a new service object
const svc = new Service({
  name: 'RetailPOS Print Helper',
  description: 'Background print service for RetailPOS web application. Enables one-click printing from web browsers.',
  script: path.join(__dirname, 'server.js'),
  nodeOptions: [],
  env: [{
    name: 'NODE_ENV',
    value: 'production'
  }]
});

// Get command line argument
const command = process.argv[2];

if (command === 'install') {
  console.log('Installing RetailPOS Print Helper service...');
  
  svc.on('install', () => {
    console.log('Service installed successfully!');
    console.log('Starting service...');
    svc.start();
  });

  svc.on('alreadyinstalled', () => {
    console.log('Service is already installed.');
  });

  svc.on('start', () => {
    console.log('Service started successfully!');
    console.log('');
    console.log('The print server is now running on http://localhost:5005');
    console.log('It will start automatically when Windows starts.');
    process.exit(0);
  });

  svc.on('error', (err) => {
    console.error('Error:', err);
    process.exit(1);
  });

  svc.install();

} else if (command === 'uninstall') {
  console.log('Uninstalling RetailPOS Print Helper service...');
  
  svc.on('uninstall', () => {
    console.log('Service uninstalled successfully!');
    process.exit(0);
  });

  svc.on('alreadyuninstalled', () => {
    console.log('Service is not installed.');
    process.exit(0);
  });

  svc.on('error', (err) => {
    console.error('Error:', err);
    process.exit(1);
  });

  svc.uninstall();

} else if (command === 'start') {
  console.log('Starting service...');
  svc.start();
  setTimeout(() => {
    console.log('Start command sent.');
    process.exit(0);
  }, 2000);

} else if (command === 'stop') {
  console.log('Stopping service...');
  svc.stop();
  setTimeout(() => {
    console.log('Stop command sent.');
    process.exit(0);
  }, 2000);

} else if (command === 'restart') {
  console.log('Restarting service...');
  svc.restart();
  setTimeout(() => {
    console.log('Restart command sent.');
    process.exit(0);
  }, 2000);

} else {
  console.log('RetailPOS Print Helper Service Manager');
  console.log('');
  console.log('Usage: node service.js <command>');
  console.log('');
  console.log('Commands:');
  console.log('  install    - Install and start the service');
  console.log('  uninstall  - Stop and remove the service');
  console.log('  start      - Start the service');
  console.log('  stop       - Stop the service');
  console.log('  restart    - Restart the service');
  process.exit(0);
}
