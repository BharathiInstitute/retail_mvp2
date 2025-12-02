@echo off
:: Silent launcher for RetailPOS Print Helper
:: Runs PowerShell script hidden
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0StartPrintHelper.ps1"
