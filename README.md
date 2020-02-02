# HVDS
High Velocity Deployment Script

Documentation not nearly completed, but:
- HVDS pulls its config from layout.xml
- layout.xml should be fairly self explanitory
- Data is taken from layout.xml and put into autounattend.xml
- HVDS\XML, HVDS\POSTCONFIG, and HVDS\LOGS are added to \HVDS under the Windows ISO
- System is built from that ISO
- Windows Update loop is built, but not currently used. This can be adjusted by changing line 183 in HVDS.ps1 (postconfig to WSUSUpdate)

Currently working:
- System update
- DC build
- VM build based on spec
- Offline Root Certificate Authority

I'm sure I'm missing a lot, but this is a start...
