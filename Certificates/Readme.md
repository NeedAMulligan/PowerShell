Local Code-Signing Framework: Overview
This system moves your machine from a "low-security" state (where any script can run) to a "Professional-Trust" state (where only your verified scripts can run).

<img width="655" height="103" alt="image" src="https://github.com/user-attachments/assets/a583585e-f035-4dec-8e96-62df05a6b480" />

2. Detailed Component Breakdown
Step 1: Establishing Trust (Create-SigningCert.ps1)
Before you can sign scripts, you need a "Digital Seal."

What it does: Creates a self-signed certificate and places it in the Trusted Root and Trusted Publisher stores.

Critical Output: * .cer file (Public Key) - Safe to share.

.pfx file (Private Key) - Keep this secure! It is stored in C:\temp with the password you defined. Anyone with this file can pretend to be you.

Step 2: Locking the System (Set-LocalSecurityPolicy.ps1)
By default, Windows is often set to RemoteSigned or Unrestricted.

What it does: Changes the system policy to AllSigned.

The Result: If you try to run a script you just wrote without signing it, Windows will now block it. This prevents "Script-Kiddie" attacks or accidental execution of downloaded files.

Step 3: The Developer Loop (Batch-SignScripts.ps1)
This is your primary tool during active development.

Usage: Point this script at your C:\Scripts folder.

What it does: It looks at every script in the folder and applies your "SharePoint Online Certificate" signature.

Timestamping: It connects to a Timestamp Authority (DigiCert) to verify when you signed the file, so it remains valid even after the certificate expires.

3. Troubleshooting & Maintenance
Why is my script still being blocked?
Modified File: If you open a signed script, change one character, and save it, the signature is broken. You must re-sign it using the Batch or Single Signer.

Trust Issue: Ensure the .cer file was successfully imported into Cert:\LocalMachine\Root. You can verify this by running certlm.msc.

Moving to a new Machine
If you get a new workstation, you don't need to create a new cert. Simply:

Copy your .pfx file to the new machine.

Right-click the .pfx and select Install PFX.

Place it in the Trusted Root and Trusted Publisher stores.

4. Security Best Practices
The PFX Password: The password in the script (P@ssword123) is a placeholder. For a production-grade setup, manually change this variable in the script before running it.

Folder Permissions: Ensure only your user account has "Write" access to C:\temp and your scripts folder to prevent others from tampering with your signed files.
