# RetailPOS Print Helper

One-click printing from web browsers for RetailPOS.

## What This Does

This small service runs in the background on your Windows PC and allows the RetailPOS web application to:
- **List all installed printers** (including USB thermal printers)
- **Print directly** without showing print dialogs
- **Remember your default printer** settings

## Quick Install

### For Users (Simple Method)

1. **Download** the `printer_backend` folder to your computer
2. **Right-click** `install.bat` → **Run as administrator**
3. **Done!** The service starts automatically

### Requirements

- Windows 10 or 11
- [Node.js](https://nodejs.org/) installed (download LTS version)
- Printer connected to your computer

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  Your Browser (RetailPOS Web App)                              │
│  http://yourstore.retailpos.com                                │
│                                                                │
│  Click "Print" button                                          │
│         │                                                      │
│         ▼                                                      │
│  Sends request to localhost:5005                               │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  Print Helper Service (This software)                          │
│  Running on localhost:5005                                     │
│                                                                │
│  - Receives print request                                      │
│  - Sends to selected printer                                   │
│         │                                                      │
│         ▼                                                      │
│  Your USB/Network Printer                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Files Included

| File | Purpose |
|------|---------|
| `install.bat` | Right-click → Run as admin to install |
| `uninstall.bat` | Right-click → Run as admin to remove |
| `start.bat` | Manually start the service (shows window) |
| `start-hidden.vbs` | Start without visible window |
| `server.js` | The actual print server |
| `service.js` | Windows Service installer |

## API Endpoints

The service runs on `http://localhost:5005` and provides:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Check if service is running |
| `/printers` | GET | List all installed printers |
| `/set-default` | POST | Set default printer |
| `/print-pdf` | POST | Print a PDF file |
| `/print-invoice` | POST | Print invoice from JSON |

## Troubleshooting

### Service not starting?
1. Open Task Manager → Services
2. Look for "RetailPOS Print Helper"
3. Right-click → Start

### Port 5005 in use?
Another program is using this port. Close it or change the port in `server.js`.

### Printer not detected?
1. Open Windows Settings → Printers & scanners
2. Make sure your printer shows there
3. Try printing a test page from Windows first

### Need to reinstall?
1. Run `uninstall.bat` as administrator
2. Run `install.bat` as administrator

## For Developers

### Manual Commands

```bash
# Install dependencies
npm install

# Start server (visible window)
npm start

# Install as Windows Service
npm run service:install

# Uninstall Windows Service
npm run service:uninstall
```

### Test the Service

```powershell
# Check health
Invoke-RestMethod -Uri "http://localhost:5005/health"

# List printers
Invoke-RestMethod -Uri "http://localhost:5005/printers"

# Set default printer
Invoke-RestMethod -Uri "http://localhost:5005/set-default" -Method Post -Body '{"printer":"POS58"}' -ContentType "application/json"
```

## License

MIT License - Free for commercial and personal use.
